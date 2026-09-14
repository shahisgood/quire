"""End-to-end smoke test against the production build with OpenRouter mocked at the network layer."""
import json, subprocess, sys, time
from playwright.sync_api import sync_playwright

PORT = 4173
BASE = f"http://localhost:{PORT}"
MODELS = {"data": [
    {"id": "anthropic/claude-sonnet-4", "canonical_slug": "anthropic/claude-sonnet-4", "name": "Anthropic: Claude Sonnet 4", "created": 1, "description": "Balanced model with vision.", "context_length": 200000,
     "architecture": {"modality": "text+image->text", "input_modalities": ["text", "image", "file"], "output_modalities": ["text"], "tokenizer": "Claude", "instruct_type": None},
     "pricing": {"prompt": "0.000003", "completion": "0.000015", "request": "0", "image": "0.0048", "web_search": "0", "internal_reasoning": "0"},
     "top_provider": {"context_length": 200000, "max_completion_tokens": 64000, "is_moderated": True},
     "supported_parameters": ["temperature", "top_p", "top_k", "max_tokens", "stop", "reasoning", "include_reasoning", "tools"]},
    {"id": "openai/o4-mini", "canonical_slug": "openai/o4-mini", "name": "OpenAI: o4 Mini", "created": 2, "description": "Reasoning model; no temperature.", "context_length": 200000,
     "architecture": {"modality": "text->text", "input_modalities": ["text"], "output_modalities": ["text"], "tokenizer": "GPT", "instruct_type": None},
     "pricing": {"prompt": "0.0000011", "completion": "0.0000044", "request": "0", "image": "0", "web_search": "0", "internal_reasoning": "0"},
     "top_provider": {"context_length": 200000, "max_completion_tokens": 100000, "is_moderated": True},
     "supported_parameters": ["max_tokens", "reasoning", "seed", "response_format", "structured_outputs"]},
    {"id": "openai/gpt-4o-mini", "canonical_slug": "openai/gpt-4o-mini", "name": "OpenAI: GPT-4o Mini", "created": 3, "description": "Cheap.", "context_length": 128000,
     "architecture": {"modality": "text+image->text", "input_modalities": ["text", "image"], "output_modalities": ["text"], "tokenizer": "GPT", "instruct_type": None},
     "pricing": {"prompt": "0.00000015", "completion": "0.0000006", "request": "0", "image": "0", "web_search": "0", "internal_reasoning": "0"},
     "top_provider": {"context_length": 128000, "max_completion_tokens": 16000, "is_moderated": True},
     "supported_parameters": ["temperature", "top_p", "max_tokens", "frequency_penalty", "presence_penalty", "seed", "stop"]},
]}

def sse_body():
    parts = [": OPENROUTER PROCESSING\n\n", ": OPENROUTER PROCESSING\n\n"]
    gid = "gen-abc123"
    def chunk(delta, extra=None):
        c = {"id": gid, "model": "anthropic/claude-sonnet-4", "choices": [{"index": 0, "delta": delta, "finish_reason": None}]}
        if extra: c.update(extra)
        return "data: " + json.dumps(c) + "\n\n"
    for w in ["Let me ", "think about ", "the question."]:
        parts.append(chunk({"reasoning": w, "content": ""}))
    text = "Here is **markdown** with code:\n\n```python\nprint('hi')\n```\n\nAnd a list:\n- one\n- two\n\n" + "".join(f"Paragraph {i}: streaming prose that keeps arriving so the list has to scroll while it grows, which is exactly where a virtualiser used to shake.\n\n" for i in range(1, 14)) + "My name in your memory is noted."
    # split into small tokens, splitting one chunk across a line boundary to test buffering
    i = 0
    while i < len(text):
        parts.append(chunk({"content": text[i:i+7]}))
        i += 7
    parts.append("data: " + json.dumps({"id": gid, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 40, "completion_tokens": 55, "total_tokens": 95, "cost": 0.00095, "completion_tokens_details": {"reasoning_tokens": 6}}}) + "\n\n")
    parts.append("data: [DONE]\n\n")
    return "".join(parts)

def main():
    srv = subprocess.Popen(["npx", "vite", "preview", "--port", str(PORT), "--strictPort"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2.5)
    errors, logs, requests = [], [], []
    try:
        with sync_playwright() as p:
            b = p.chromium.launch()
            iphone = p.devices["iPhone 14"]
            ctx = b.new_context(**iphone, service_workers="block")
            page = ctx.new_page()
            page.on("pageerror", lambda e: errors.append(f"PAGEERROR {e}"))
            page.on("console", lambda m: (errors if m.type == "error" else logs).append(f"{m.type}: {m.text}"))

            def handle(route, request):
                url = request.url
                requests.append((request.method, url))
                if url.endswith("/api/v1/models"):
                    route.fulfill(status=200, content_type="application/json", body=json.dumps(MODELS))
                elif "/api/v1/chat/completions" in url:
                    body = json.loads(request.post_data or "{}")
                    if body.get("stream"):
                        route.fulfill(status=200, headers={"content-type": "text/event-stream"}, body=sse_body())
                    else:
                        sys_prompt = body["messages"][0]["content"] if body["messages"] else ""
                        if "durable facts" in sys_prompt:
                            out = {"operations": [{"op": "add", "text": "Is called Hasan and builds PWAs.", "category": "identity"}]}
                            content = "```json\n" + json.dumps(out) + "\n```"
                        else:
                            content = "Markdown and memory test"
                        route.fulfill(status=200, content_type="application/json", body=json.dumps({"id": "gen-x", "model": body["model"], "choices": [{"message": {"role": "assistant", "content": content}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 10, "completion_tokens": 5}}))
                elif "/api/v1/generation" in url:
                    route.fulfill(status=200, content_type="application/json", body=json.dumps({"data": {"id": "gen-abc123", "total_cost": 0.00101, "tokens_prompt": 40, "tokens_completion": 55, "native_tokens_prompt": 42, "native_tokens_completion": 57, "native_tokens_reasoning": 6, "model": "anthropic/claude-sonnet-4", "provider_name": "Anthropic"}}))
                elif url.endswith("/api/v1/key"):
                    route.fulfill(status=200, content_type="application/json", body=json.dumps({"data": {"label": "test key", "usage": 1.23, "limit": 10, "limit_remaining": 8.77, "is_free_tier": False, "rate_limit": {"requests": 200, "interval": "10s"}}}))
                else:
                    route.fulfill(status=404, body="nope")
            ctx.route("https://openrouter.ai/**", handle)

            page.goto(BASE + "/")
            page.wait_for_timeout(800)
            page.screenshot(path="/home/claude/quire/shots/01-first-launch.png")
            assert page.get_by_text("Quire needs an OpenRouter key").count() == 1, "empty state missing"

            page.get_by_role("button", name="Add key").click()
            page.wait_for_timeout(300)
            page.get_by_label("OpenRouter API key").fill("sk-or-v1-test-key-1234")
            page.get_by_role("button", name="Save key").click()
            page.wait_for_timeout(600)
            page.screenshot(path="/home/claude/quire/shots/02-connection.png")
            assert page.get_by_text("test key").count() >= 1, "key meta not shown"

            page.get_by_role("button", name="Back", exact=True).click(); page.wait_for_timeout(200)
            page.get_by_role("button", name="Back", exact=True).click(); page.wait_for_timeout(300)
            page.get_by_text("Talking to Claude Sonnet 4").wait_for(timeout=3000)

            # model picker
            page.get_by_role("button", name="Change model").click()
            page.wait_for_timeout(400)
            page.screenshot(path="/home/claude/quire/shots/03-picker.png")
            page.get_by_label("Search models").fill("o4")
            page.wait_for_timeout(200)
            page.get_by_text("OpenAI: o4 Mini").first.click()
            page.wait_for_timeout(300)
            assert page.get_by_text("Talking to o4 Mini").count() == 1, "model switch failed"

            # capability-aware settings: o4-mini has no temperature
            page.get_by_role("button", name="Quick settings").click(); page.wait_for_timeout(400)
            assert page.get_by_text("Temperature").count() == 0, "temperature shown for a model without it"
            assert page.get_by_text("Reasoning", exact=True).count() >= 1, "reasoning control missing"
            page.screenshot(path="/home/claude/quire/shots/04-quick-o4.png")
            page.get_by_role("button", name="Close", exact=True).first.click(); page.wait_for_timeout(200)

            # back to sonnet and send
            page.get_by_role("button", name="Change model").click(); page.wait_for_timeout(300)
            page.get_by_label("Search models").fill("sonnet"); page.wait_for_timeout(200)
            page.get_by_text("Anthropic: Claude Sonnet 4").first.click(); page.wait_for_timeout(300)
            page.get_by_role("textbox", name="Message").fill("Hello, my name is Hasan and I build PWAs. Show me some markdown.")
            # Bug 1: typed text must be ink-coloured, not background-coloured, in both themes
            def input_ok():
                return page.evaluate("""() => { const t = document.querySelector('textarea[aria-label=Message]'); const cs = getComputedStyle(t); const root = getComputedStyle(document.documentElement); const norm = (c) => { const d = document.createElement('div'); d.style.color = c; document.body.appendChild(d); const r = getComputedStyle(d).color; d.remove(); return r; }; return { color: cs.color, fill: cs.webkitTextFillColor, ink: norm(root.getPropertyValue('--c-ink').trim()), base: norm(root.getPropertyValue('--c-base').trim()), theme: document.documentElement.dataset.theme }; }""")
            r = input_ok(); assert r["color"] == r["ink"] and r["fill"] == r["ink"] and r["color"] != r["base"], f"dark input colour wrong: {r}"
            page.screenshot(path="/home/claude/quire/shots/04b-typed-dark.png")
            page.evaluate("() => { document.documentElement.dataset.theme = 'light'; }")
            r = input_ok(); assert r["color"] == r["ink"] and r["color"] != r["base"], f"light input colour wrong: {r}"
            page.screenshot(path="/home/claude/quire/shots/04c-typed-light.png")
            page.evaluate("() => { document.documentElement.dataset.theme = 'dark'; }")
            # Bug 2: sample the scroller every frame while streaming; a pinned list must never move backwards
            page.get_by_role("button", name="Send").click()
            page.wait_for_timeout(120)
            page.evaluate("""() => { window.__samples = []; const tick = () => { const el = document.getElementById('messages'); if (el) window.__samples.push([el.scrollTop, el.scrollHeight - el.clientHeight]); if (window.__samples.length < 400) requestAnimationFrame(tick); }; requestAnimationFrame(tick); }""")
            page.wait_for_timeout(600)
            page.screenshot(path="/home/claude/quire/shots/05-streaming.png")
            page.wait_for_timeout(3500)
            samples = page.evaluate("() => window.__samples")
            # A drop is jitter only if the list is then away from the bottom; a clamp after content shrinks is not.
            jitter = [(i, a, b) for i, (a, b) in enumerate(zip(samples, samples[1:])) if b[0] < a[0] - 0.5 and b[0] < b[1] - 1]
            for i, a, b in jitter: print(f"  jitter at frame {i}: {a} -> {b}")
            assert not jitter, f"scroll jitter: {len(jitter)} events in {len(samples)} frames"
            assert samples[-1][0] > 300 and abs(samples[-1][0] - samples[-1][1]) < 2, f"list not pinned at the end: {samples[-1]}"
            print(f"scroll samples: {len(samples)} frames, 0 jitter events, final {samples[-1][0]:.0f}px of {samples[-1][1]:.0f}px")
            page.screenshot(path="/home/claude/quire/shots/06-reply.png", full_page=False)
            html = page.content()
            assert "hljs" in html and "<strong>markdown</strong>" in html, "markdown not rendered"
            assert page.get_by_text("Reasoning").count() >= 1, "reasoning block missing"
            page.wait_for_timeout(2500)  # generation reconciliation + extraction
            assert page.locator("text=/\\$0\\.001/").count() >= 1, "authoritative cost not applied: " + page.locator(".num").all_inner_texts().__repr__()

            # memory screen
            page.get_by_role("button", name="All chats").click(); page.wait_for_timeout(300)
            page.screenshot(path="/home/claude/quire/shots/07-list.png")
            assert page.get_by_text("Markdown and memory test").count() >= 1, "chat missing from list"
            assert page.locator("text=$0.0010").count() >= 2, "chat row cost not reconciled"
            page.get_by_role("button", name="Memory", exact=True).click(); page.wait_for_timeout(400)
            page.screenshot(path="/home/claude/quire/shots/08-memory.png")
            assert page.get_by_text("Is called Hasan and builds PWAs.").count() == 1, "extraction did not land"

            # second request must include the memory block in the system message
            page.get_by_role("button", name="Back", exact=True).click(); page.wait_for_timeout(300)
            page.get_by_role("textbox", name="Message").fill("Second message")
            page.get_by_role("button", name="Send").click(); page.wait_for_timeout(2500)
            streams = [r for r in requests if "chat/completions" in r[1]]
            assert len(streams) >= 3, f"expected completions, got {streams}"

            # request snapshot check via long-press menu
            page.get_by_role("button", name="Message actions").last.click(); page.wait_for_timeout(300)
            page.get_by_text("Show the request").click(); page.wait_for_timeout(300)
            body = page.locator("pre").last.inner_text()
            assert "<user_memory>" in body and "Is called Hasan" in body, "memory not injected"
            assert '"usage"' in body and '"include": true' in body, "usage accounting missing"
            page.screenshot(path="/home/claude/quire/shots/09-request.png")
            page.get_by_role("button", name="Close", exact=True).click(); page.wait_for_timeout(200)

            # reload: last chat restored, messages persisted
            page.reload(); page.wait_for_timeout(900)
            assert page.get_by_text("Second message").count() >= 1, "persistence failed after reload"
            page.screenshot(path="/home/claude/quire/shots/10-after-reload.png")

            # desktop layout
            page.set_viewport_size({"width": 1200, "height": 800}); page.wait_for_timeout(500)
            page.screenshot(path="/home/claude/quire/shots/11-desktop.png")
            b.close()
    finally:
        srv.terminate()
        print("errors:", len(errors))
        for e in errors: print("  ", e[:600])
    print("requests:", len(requests))
    for r in requests: print("  ", r[0], r[1][:90])
    if errors: sys.exit(1)
    print("E2E OK")

if __name__ == "__main__":
    main()
