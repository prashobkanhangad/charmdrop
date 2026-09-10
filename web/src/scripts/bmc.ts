export function mountBmcTriggers() {
  document.addEventListener("click", (event) => {
    const trigger =
      event.target instanceof Element
        ? event.target.closest<HTMLAnchorElement>("a[data-bmc-open]")
        : null;
    if (!trigger) return;

    event.preventDefault();
    void openWidget(trigger.href);
  });
}

async function openWidget(fallbackUrl: string) {
  const widget = await waitForWidget();
  if (widget) {
    widget.click();
    return;
  }
  window.open(fallbackUrl, "_blank", "noopener,noreferrer");
}

function waitForWidget(timeoutMs = 2500): Promise<HTMLElement | null> {
  const existing = document.getElementById("bmc-wbtn");
  if (existing instanceof HTMLElement) return Promise.resolve(existing);

  return new Promise((resolve) => {
    const finish = (node: HTMLElement | null) => {
      observer.disconnect();
      window.clearTimeout(timer);
      resolve(node);
    };

    const observer = new MutationObserver(() => {
      const node = document.getElementById("bmc-wbtn");
      if (node instanceof HTMLElement) finish(node);
    });
    observer.observe(document.body, { childList: true, subtree: true });

    const timer = window.setTimeout(() => finish(null), timeoutMs);
  });
}
