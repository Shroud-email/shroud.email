import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';

export async function uploadSarif({
  file,
  sourceRoot,
  category,
  env = process.env,
  request = fetch,
  wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
}) {
  // Local Depot runs can include patches absent from the reported GitHub commit.
  if (env.GITHUB_EVENT_NAME === 'api' || !env.GITHUB_REF) {
    console.log(
      'Skipping GitHub SARIF upload for a local/ref-less run; report retained as a Depot artifact.',
    );
    return;
  }

  const report = JSON.parse(await readFile(file, 'utf8'));
  for (const run of report.runs) {
    run.automationDetails = { ...run.automationDetails, id: `${category}/` };
    if (sourceRoot !== '.') {
      const prefixLocation = (location) => {
        if (
          location?.uri &&
          !location.uri.startsWith('/') &&
          !/^[a-z][a-z0-9+.-]*:/i.test(location.uri)
        ) {
          location.uri = path.posix.join(sourceRoot, location.uri);
        }
      };
      const visit = (value) => {
        if (!value || typeof value !== 'object') return;
        prefixLocation(value.artifactLocation);
        for (const child of Object.values(value)) visit(child);
      };
      visit(run.results);
      for (const artifact of run.artifacts ?? [])
        prefixLocation(artifact.location);
    }
  }

  const endpoint = `${env.GITHUB_API_URL || 'https://api.github.com'}/repos/${env.GITHUB_REPOSITORY}/code-scanning/sarifs`;
  const headers = {
    Authorization: `Bearer ${env.GITHUB_TOKEN}`,
    Accept: 'application/vnd.github+json',
    'Content-Type': 'application/json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  const call = async (url, options = {}) => {
    const response = await request(url, {
      ...options,
      headers,
      signal: AbortSignal.timeout(30000),
    });
    const body = await response.json();
    if (!response.ok)
      throw new Error(`GitHub SARIF API ${response.status}: ${body.message}`);
    return body;
  };
  const { id } = await call(endpoint, {
    method: 'POST',
    body: JSON.stringify({
      commit_sha: env.GITHUB_SHA,
      ref: env.GITHUB_REF,
      checkout_uri: pathToFileURL(`${env.GITHUB_WORKSPACE}/`).href,
      sarif: gzipSync(JSON.stringify(report)).toString('base64'),
      tool_name: report.runs[0].tool.driver.name,
      validate: true,
    }),
  });

  for (let attempt = 0; attempt < 24; attempt++) {
    const result = await call(`${endpoint}/${id}`);
    if (result.processing_status === 'complete') {
      console.log(`GitHub SARIF upload ${id} processed successfully.`);
      return;
    }
    if (result.processing_status === 'failed') {
      throw new Error(
        `GitHub SARIF processing failed: ${(result.errors ?? []).join('; ')}`,
      );
    }
    await wait(5000);
  }
  throw new Error(
    `GitHub SARIF upload ${id} did not finish processing within two minutes.`,
  );
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const [file, sourceRoot, category] = process.argv.slice(2);
  await uploadSarif({ file, sourceRoot, category });
}
