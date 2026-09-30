import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { gunzipSync } from 'node:zlib';
import { uploadSarif } from './upload-sarif.mjs';

const env = {
  GITHUB_EVENT_NAME: 'push',
  GITHUB_REF: 'refs/heads/main',
  GITHUB_SHA: '1234567890abcdef1234567890abcdef12345678',
  GITHUB_WORKSPACE: '/work/repo',
  GITHUB_REPOSITORY: 'Shroud-email/shroud.email',
  GITHUB_TOKEN: 'test-token',
};
const response = (body, status = 200) =>
  new Response(JSON.stringify(body), { status });

async function withReport(runTest) {
  const directory = await mkdtemp(path.join(tmpdir(), 'sarif-test-'));
  const file = path.join(directory, 'report.sarif');
  await writeFile(
    file,
    JSON.stringify({
      version: '2.1.0',
      runs: [
        {
          tool: { driver: { name: 'Sobelow' } },
          artifacts: [{ location: { uri: 'config/prod.exs' } }],
          results: [
            {
              locations: [
                {
                  physicalLocation: {
                    artifactLocation: { uri: 'lib/shroud/mailer.ex' },
                  },
                },
              ],
              relatedLocations: [
                {
                  physicalLocation: {
                    artifactLocation: { uri: 'https://example.com/reference' },
                  },
                },
              ],
              partialFingerprints: {
                primaryLocationLineHash: 'original-fingerprint',
              },
            },
          ],
        },
      ],
    }),
  );
  try {
    await runTest({
      file,
      sourceRoot: 'shroud.email',
      category: 'sobelow',
      env,
      wait: async () => {},
    });
  } finally {
    await rm(directory, { recursive: true });
  }
}

test('uploads through the public API with monorepo paths and waits for processing', async () => {
  await withReport(async (options) => {
    const calls = [];
    const responses = [
      response({ id: 'upload-17' }, 202),
      response({ processing_status: 'pending' }),
      response({ processing_status: 'complete' }),
    ];
    await uploadSarif({
      ...options,
      request: async (url, request) => {
        calls.push({ url, request });
        return responses.shift();
      },
    });
    assert.equal(calls.length, 3);
    assert.equal(
      calls[0].url,
      'https://api.github.com/repos/Shroud-email/shroud.email/code-scanning/sarifs',
    );
    assert.equal(calls[0].request.method, 'POST');
    assert.equal(calls[0].request.headers.Authorization, 'Bearer test-token');
    const payload = JSON.parse(calls[0].request.body);
    assert.equal(
      payload.commit_sha,
      '1234567890abcdef1234567890abcdef12345678',
    );
    assert.equal(payload.ref, 'refs/heads/main');
    assert.equal(payload.checkout_uri, 'file:///work/repo/');
    assert.equal(payload.validate, true);
    assert.equal(payload.tool_name, 'Sobelow');
    assert.equal(payload.workflow_run_id, undefined);
    const run = JSON.parse(gunzipSync(Buffer.from(payload.sarif, 'base64')))
      .runs[0];
    assert.equal(run.automationDetails.id, 'sobelow/');
    assert.equal(run.artifacts[0].location.uri, 'shroud.email/config/prod.exs');
    assert.equal(
      run.results[0].locations[0].physicalLocation.artifactLocation.uri,
      'shroud.email/lib/shroud/mailer.ex',
    );
    assert.equal(
      run.results[0].relatedLocations[0].physicalLocation.artifactLocation.uri,
      'https://example.com/reference',
    );
    assert.equal(
      run.results[0].partialFingerprints.primaryLocationLineHash,
      'original-fingerprint',
    );
    assert.equal(calls[1].url, `${calls[0].url}/upload-17`);
  });
});

test('root-based PR reports keep their paths and full merge ref', async () => {
  await withReport(async (options) => {
    await uploadSarif({
      ...options,
      sourceRoot: '.',
      category: 'trivy-filesystem',
      env: {
        ...env,
        GITHUB_REF: 'refs/pull/194/merge',
        GITHUB_EVENT_NAME: 'pull_request',
      },
      request: async (url, request) => {
        if (request.method !== 'POST')
          return response({ processing_status: 'complete' });
        const payload = JSON.parse(request.body);
        assert.equal(payload.ref, 'refs/pull/194/merge');
        const run = JSON.parse(gunzipSync(Buffer.from(payload.sarif, 'base64')))
          .runs[0];
        assert.equal(
          run.results[0].locations[0].physicalLocation.artifactLocation.uri,
          'lib/shroud/mailer.ex',
        );
        assert.equal(run.automationDetails.id, 'trivy-filesystem/');
        return response({ id: 'pr-upload' }, 202);
      },
    });
  });
});

test('API runs even with a ref, and ref-less runs, never write to GitHub', async () => {
  for (const context of [
    { ...env, GITHUB_EVENT_NAME: 'api' },
    { ...env, GITHUB_REF: '' },
  ]) {
    await uploadSarif({
      env: context,
      request: async () =>
        assert.fail('Must not attribute local patches to a GitHub commit'),
    });
  }
});

test('API rejection and asynchronous processing failure fail the job', async () => {
  await withReport(async (options) => {
    await assert.rejects(
      uploadSarif({
        ...options,
        request: async () => response({ message: 'Forbidden' }, 403),
      }),
      /GitHub SARIF API 403: Forbidden/,
    );
    await assert.rejects(
      uploadSarif({
        ...options,
        request: async (url, request) =>
          request.method === 'POST'
            ? response({ id: 'bad-upload' }, 202)
            : response({
                processing_status: 'failed',
                errors: ['Invalid location'],
              }),
      }),
      /processing failed: Invalid location/,
    );
  });
});

test('processing timeout is not reported as success', async () => {
  await withReport(async (options) => {
    let polls = 0;
    await assert.rejects(
      uploadSarif({
        ...options,
        request: async (url, request) => {
          if (request.method === 'POST')
            return response({ id: 'pending-upload' }, 202);
          polls++;
          return response({ processing_status: 'pending' });
        },
      }),
      /did not finish processing/,
    );
    assert.equal(polls, 24);
  });
});
