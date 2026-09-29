// Ambient types for the bunny.net edge runtime globals that aren't shipped in
// the @bunny.net/edgescript-sdk type definitions (HTMLRewriter + its Element
// type). These exist at runtime on bunny's edge; declaring them here lets
// `deno check` pass. Only the slice of the API we use is typed.
// Ref: https://docs.bunny.net/scripting/html-rewriter

declare global {
  /** Options accepted by content-mutation methods on {@link Element}. */
  interface ContentOptions {
    html?: boolean;
  }

  /** An HTML element matched by an {@link HTMLRewriter} selector. */
  interface HtmlRewriterElement {
    tagName: string;
    getAttribute(name: string): string | null;
    hasAttribute(name: string): boolean;
    setAttribute(name: string, value: string): HtmlRewriterElement;
    removeAttribute(name: string): HtmlRewriterElement;
    setInnerContent(content: string, options?: ContentOptions): HtmlRewriterElement;
    before(content: string, options?: ContentOptions): HtmlRewriterElement;
    after(content: string, options?: ContentOptions): HtmlRewriterElement;
    remove(): HtmlRewriterElement;
  }

  /** Handler invoked for each element matching a selector. */
  interface ElementHandler {
    element?(el: HtmlRewriterElement): void | Promise<void>;
  }

  /**
   * Streaming HTML rewriter. Transforms a {@link Response} body in place,
   * calling handlers as matching elements stream through. Returns a new
   * Response (same headers, minus Content-Length) with the rewritten body.
   */
  class HTMLRewriter {
    on(selector: string, handlers: ElementHandler): this;
    transform(response: Response): Response;
  }
}

export {};
