interface Page {
  title: string;
  href: string;
}

interface Section {
  title: string;
  links: Page[];
}

const navigation: Section[] = [
  {
    title: "Introduction",
    links: [{ title: "Welcome", href: "/docs/" }],
  },
  {
    title: "Product details",
    links: [
      { title: "Custom domains", href: "/docs/product/custom-domains/" },
      { title: "Spam", href: "/docs/product/spam/" },
    ],
  },
  {
    title: "Deployment",
    links: [
      { title: "Considerations", href: "/docs/deployment/considerations/" },
      { title: "Self-host", href: "/docs/deployment/self-host/" },
      { title: "Upgrading", href: "/docs/deployment/upgrading/" },
    ],
  },
  {
    title: "API",
    links: [
      { title: "Authentication", href: "/docs/api/authentication/" },
      { title: "/aliases", href: "/docs/api/aliases/" },
      { title: "/domains", href: "/docs/api/domains/" },
    ],
  },
];

export default navigation;
