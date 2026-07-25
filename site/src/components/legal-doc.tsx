import Link from "next/link";
import type { ReactNode } from "react";
import type { LegalBlock, LegalDoc as Doc } from "@/lib/legal";

/* Legal copy is stored as plain strings (see src/lib/legal.ts) so it stays
   readable and reviewable as prose. Three inline marks survive that trip:
   **strong**, [label](href) and `code`. Anything more expressive belongs in a
   block type, not in the string. */
const INLINE = /\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`/g;

function InlineLink({ href, children }: { href: string; children: ReactNode }) {
  const className =
    "text-ink underline decoration-line-strong underline-offset-[3px] transition-colors hover:text-accent hover:decoration-accent";

  // Internal routes go through next/link so basePath is applied for us;
  // next/image is the only thing on this site that needs it spelled out.
  return href.startsWith("/") ? (
    <Link href={href} className={className}>
      {children}
    </Link>
  ) : (
    <a href={href} target="_blank" rel="noreferrer" className={className}>
      {children}
    </a>
  );
}

function inline(text: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  let cursor = 0;
  let match: RegExpExecArray | null;

  INLINE.lastIndex = 0;
  while ((match = INLINE.exec(text)) !== null) {
    if (match.index > cursor) nodes.push(text.slice(cursor, match.index));
    const key = `${match.index}`;

    if (match[1] !== undefined) {
      nodes.push(
        <strong key={key} className="font-semibold text-ink">
          {match[1]}
        </strong>,
      );
    } else if (match[2] !== undefined) {
      nodes.push(
        <InlineLink key={key} href={match[3]}>
          {match[2]}
        </InlineLink>,
      );
    } else {
      nodes.push(
        <code
          key={key}
          className="readout rounded-[4px] border border-line bg-panel-2 px-1 py-px text-[0.85em] break-words text-ink-soft"
        >
          {match[4]}
        </code>,
      );
    }

    cursor = match.index + match[0].length;
  }
  if (cursor < text.length) nodes.push(text.slice(cursor));

  return nodes;
}

function Block({ block }: { block: LegalBlock }) {
  switch (block.kind) {
    case "p":
      return (
        <p className="text-[15px] leading-[1.75] text-muted">
          {inline(block.text)}
        </p>
      );

    case "list":
      return (
        <ul className="flex flex-col gap-3">
          {block.items.map((item, i) => (
            <li
              key={i}
              className="relative pl-5 text-[15px] leading-[1.75] text-muted before:absolute before:top-[0.7em] before:left-0 before:h-1 before:w-1 before:rounded-full before:bg-accent"
            >
              {inline(item)}
            </li>
          ))}
        </ul>
      );

    case "callout":
      return (
        <div className="rounded-xl border border-line bg-panel p-5 shadow-[var(--shadow)]">
          <div className="eyebrow">{block.title}</div>
          <p className="mt-2.5 text-[15px] leading-[1.75] text-ink-soft">
            {inline(block.text)}
          </p>
        </div>
      );
  }
}

/**
 * Renders a whole legal document: masthead, contents rail and the sections.
 *
 * Deliberately static — no scroll-reveal. These pages are read under a
 * verification review as often as by a visitor, and copy that fades in on
 * scroll reads as copy that might not be there.
 */
export function LegalDoc({ doc, other }: { doc: Doc; other: { href: string; label: string } }) {
  return (
    <>
      <section className="border-b border-line px-5 py-16 sm:px-8 lg:py-20">
        <div className="mx-auto max-w-6xl">
          <div className="eyebrow">Legal</div>
          <h1 className="display mt-3 text-[clamp(2.25rem,5vw,3.5rem)]">
            {doc.title}
          </h1>
          <p className="readout mt-5 text-[13px] text-muted">
            Effective {doc.effective}
          </p>
          <p className="mt-6 max-w-[62ch] text-[17px] leading-relaxed text-muted">
            {doc.lede}
          </p>
        </div>
      </section>

      <div className="mx-auto grid max-w-6xl gap-12 px-5 py-16 sm:px-8 lg:grid-cols-[minmax(0,15rem)_minmax(0,1fr)] lg:gap-16 lg:py-20">
        <nav aria-label="On this page" className="lg:sticky lg:top-20 lg:self-start">
          <div className="eyebrow">Contents</div>
          <ol className="mt-4 flex flex-col gap-2.5">
            {doc.sections.map((section, i) => (
              <li key={section.id} className="flex gap-3 text-[13.5px] leading-snug">
                <span className="readout shrink-0 text-muted/60">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <a
                  href={`#${section.id}`}
                  className="text-muted transition-colors hover:text-ink"
                >
                  {section.heading}
                </a>
              </li>
            ))}
          </ol>
        </nav>

        <div className="flex flex-col gap-12">
          {doc.sections.map((section) => (
            <section key={section.id} id={section.id} className="scroll-mt-24">
              <h2 className="display-sm text-[clamp(1.3rem,2.2vw,1.6rem)]">
                {section.heading}
              </h2>
              <div className="mt-4 flex max-w-[68ch] flex-col gap-4">
                {section.blocks.map((block, i) => (
                  <Block key={i} block={block} />
                ))}
              </div>
            </section>
          ))}

          <div className="border-t border-line pt-8">
            <Link
              href={other.href}
              className="text-[15px] text-muted transition-colors hover:text-ink"
            >
              Read the {other.label} →
            </Link>
          </div>
        </div>
      </div>
    </>
  );
}
