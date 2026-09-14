import { memo, useEffect, useMemo, useRef, useState } from 'react';
import ReactMarkdown, { type Components } from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import 'katex/dist/katex.min.css';
import { Icons } from './ui';

type HLJS = typeof import('highlight.js/lib/core').default;
let hljsPromise: Promise<HLJS> | null = null;
async function loadHljs(): Promise<HLJS> {
  if (!hljsPromise) {
    hljsPromise = (async () => {
      const core = (await import('highlight.js/lib/core')).default;
      const langs: Array<[string[], () => Promise<{ default: Parameters<HLJS['registerLanguage']>[1] }>]> = [
        [['javascript', 'js', 'jsx'], () => import('highlight.js/lib/languages/javascript')],
        [['typescript', 'ts', 'tsx'], () => import('highlight.js/lib/languages/typescript')],
        [['python', 'py'], () => import('highlight.js/lib/languages/python')],
        [['bash', 'sh', 'shell', 'zsh'], () => import('highlight.js/lib/languages/bash')],
        [['json'], () => import('highlight.js/lib/languages/json')],
        [['yaml', 'yml'], () => import('highlight.js/lib/languages/yaml')],
        [['xml', 'html', 'svg'], () => import('highlight.js/lib/languages/xml')],
        [['css'], () => import('highlight.js/lib/languages/css')],
        [['sql'], () => import('highlight.js/lib/languages/sql')],
        [['rust', 'rs'], () => import('highlight.js/lib/languages/rust')],
        [['go', 'golang'], () => import('highlight.js/lib/languages/go')],
        [['java'], () => import('highlight.js/lib/languages/java')],
        [['c', 'h'], () => import('highlight.js/lib/languages/c')],
        [['cpp', 'c++', 'cc'], () => import('highlight.js/lib/languages/cpp')],
        [['csharp', 'cs'], () => import('highlight.js/lib/languages/csharp')],
        [['swift'], () => import('highlight.js/lib/languages/swift')],
        [['kotlin', 'kt'], () => import('highlight.js/lib/languages/kotlin')],
        [['markdown', 'md'], () => import('highlight.js/lib/languages/markdown')],
        [['diff'], () => import('highlight.js/lib/languages/diff')],
        [['plaintext', 'text', 'txt'], () => import('highlight.js/lib/languages/plaintext')],
      ];
      await Promise.all(langs.map(async ([names, load]) => { const m = await load(); for (const n of names) core.registerLanguage(n, m.default); }));
      return core;
    })();
  }
  return hljsPromise;
}

/** Close an unbalanced code fence so a block in progress renders as a block, not raw text. */
export function stabilise(md: string): string {
  const fences = md.match(/^\s{0,3}(```|~~~)/gm);
  if (fences && fences.length % 2 === 1) {
    const last = fences[fences.length - 1]!.trim();
    return `${md}\n${last}`;
  }
  return md;
}

function CodeBlock({ lang, code, streaming }: { lang: string; code: string; streaming: boolean }) {
  const [html, setHtml] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (streaming || !lang || lang === 'text' || lang === 'plaintext' || code.length > 60_000) { setHtml(null); return; }
    let live = true;
    void loadHljs().then((h) => {
      if (!live) return;
      const l = h.getLanguage(lang) ? lang : null;
      if (!l) { setHtml(null); return; }
      try { setHtml(h.highlight(code, { language: l, ignoreIllegals: true }).value); } catch { setHtml(null); }
    });
    return () => { live = false; };
  }, [code, lang, streaming]);
  const copy = async () => {
    try { await navigator.clipboard.writeText(code); setCopied(true); setTimeout(() => setCopied(false), 1400); } catch { /* clipboard blocked */ }
  };
  return (
    <pre className="chrome">
      <div className="code-head">
        <span>{lang || 'code'}</span>
        <button type="button" onClick={() => void copy()} className="pressable inline-flex min-h-[32px] items-center gap-1 px-2 text-ink2" aria-label="Copy code">
          {copied ? <Icons.check size={14} /> : <Icons.copy size={14} />}<span>{copied ? 'Copied' : 'Copy'}</span>
        </button>
      </div>
      {html ? <code className="selectable" dangerouslySetInnerHTML={{ __html: html }} /> : <code className="selectable">{code}</code>}
    </pre>
  );
}

function makeComponents(streaming: boolean): Components {
  return {
    pre: ({ children }) => <>{children}</>,
    code: ({ className, children, node, ...rest }) => {
      const match = /language-([\w+-]+)/.exec(className ?? '');
      const text = String(children ?? '');
      const isBlock = Boolean(match) || text.includes('\n');
      if (!isBlock) return <code className={className} {...rest}>{children}</code>;
      return <CodeBlock lang={match?.[1] ?? ''} code={text.replace(/\n$/, '')} streaming={streaming} />;
    },
    a: ({ href, children }) => <a href={href} target="_blank" rel="noopener noreferrer">{children}</a>,
    table: ({ children }) => <table>{children}</table>,
    input: ({ checked, type }) => (type === 'checkbox' ? <input type="checkbox" checked={Boolean(checked)} readOnly /> : null),
  };
}

const remarkPlugins = [remarkGfm, remarkMath];
const rehypePlugins = [[rehypeKatex, { throwOnError: false, strict: false, output: 'htmlAndMathml' }]] as never;

export const Markdown = memo(function Markdown({ content, streaming = false }: { content: string; streaming?: boolean }) {
  // While streaming, re-parse at most every ~60ms; the caret keeps the tail feeling live.
  const [shown, setShown] = useState(content);
  const pending = useRef(content);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    pending.current = content;
    if (!streaming) { if (timer.current) { clearTimeout(timer.current); timer.current = null; } setShown(content); return; }
    if (!timer.current) timer.current = setTimeout(() => { timer.current = null; setShown(pending.current); }, 60);
  }, [content, streaming]);
  const src = useMemo(() => (streaming ? stabilise(shown) : shown), [shown, streaming]);
  const components = useMemo(() => makeComponents(streaming), [streaming]);
  return (
    <div className={`prose selectable ${streaming ? 'caret' : ''}`}>
      <ReactMarkdown remarkPlugins={remarkPlugins} rehypePlugins={rehypePlugins} components={components} skipHtml>{src}</ReactMarkdown>
    </div>
  );
});

export default Markdown;
