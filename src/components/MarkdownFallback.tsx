/** Tiny synchronous fallback shown while the markdown chunk loads. */
export function PlainFallback({ content, streaming }: { content: string; streaming?: boolean }) {
  return <div className={`prose selectable whitespace-pre-wrap ${streaming ? 'caret' : ''}`}>{content}</div>;
}
