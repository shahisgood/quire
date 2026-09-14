import { Suspense, lazy, useEffect, useState } from 'react';
import { useRegisterSW } from 'virtual:pwa-register/react';
import { installViewportTracking } from '@/lib/viewport';
import { completeOAuthIfPresent } from '@/lib/openrouter';
import { clientConfig, useApp } from '@/store/app';
import { useChat } from '@/store/chat';
import { useChats } from '@/store/chats';
import { useModels } from '@/store/models';
import { pathToRoute, useUI } from '@/store/ui';
import { ChatScreen } from '@/screens/Chat';
import { ChatListScreen } from '@/screens/ChatList';
import { SheetHost } from '@/components/Sheets';
import { Bar, DialogHost, ToastHost } from '@/components/ui';

const SettingsScreen = lazy(() => import('@/screens/Settings').then((m) => ({ default: m.SettingsScreen })));
const MemoryScreen = lazy(() => import('@/screens/Memory').then((m) => ({ default: m.MemoryScreen })));

function useInit(): boolean {
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const stop = installViewportTracking();
    (async () => {
      await useApp.getState().init();
      await useChats.getState().reload();
      useUI.setState({ route: pathToRoute(location.pathname) });
      const oauth = await completeOAuthIfPresent(clientConfig());
      if (oauth.key) { useApp.getState().setApiKey(oauth.key); useUI.getState().toast('Signed in to OpenRouter'); useUI.getState().navigate({ name: 'chat', chatId: null }, true); }
      else if (oauth.error) { useUI.getState().toast(oauth.error, { label: 'Settings', onClick: () => useUI.getState().navigate({ name: 'settings', section: 'connection' }) }, 8000); }
      setReady(true);
      void useModels.getState().load();
    })().catch((e) => { console.error(e); setReady(true); });
    return stop;
  }, []);
  return ready;
}

function UpdateBar() {
  const { needRefresh: [needRefresh], updateServiceWorker } = useRegisterSW({ onRegisteredSW(_url, r) { if (r) setInterval(() => void r.update(), 60 * 60 * 1000); } });
  const generating = useChat((s) => s.generating);
  const setUpdate = useUI((s) => s.setUpdate);
  const [hidden, setHidden] = useState(false);
  useEffect(() => { setUpdate(needRefresh, needRefresh ? () => void updateServiceWorker(true) : null); }, [needRefresh, setUpdate, updateServiceWorker]);
  if (!needRefresh || hidden) return null;
  return <Bar action={generating ? undefined : 'Reload'} onAction={() => void updateServiceWorker(true)} onClose={() => setHidden(true)}>{generating ? 'Update ready. It will apply after this reply finishes.' : 'A new version of Quire is ready.'}</Bar>;
}

function BackupBar() {
  const s = useApp((st) => st.settings);
  const navigate = useUI((st) => st.navigate);
  const [dismissed, setDismissed] = useState(false);
  const chats = useChats((st) => st.chats.length);
  const stale = chats > 0 && ((s.messagesSinceExport ?? 0) >= 200 || (s.lastExportAt ? Date.now() - s.lastExportAt > 30 * 86400_000 : (s.messagesSinceExport ?? 0) >= 40));
  if (!stale || dismissed) return null;
  return <Bar action="Export" onAction={() => navigate({ name: 'settings', section: 'data' })} onClose={() => setDismissed(true)}>{s.lastExportAt ? 'It has been a while since your last backup.' : 'Nothing here is backed up yet. Export a copy.'}</Bar>;
}

function OfflineBar() {
  const online = useApp((s) => s.online);
  if (online) return null;
  return <Bar>Offline. Chats are readable and drafts are saved; sending resumes when you are back.</Bar>;
}

function Screen() {
  const route = useUI((s) => s.route);
  const wide = useUI((s) => s.wide);
  const fallback = <div className="flex flex-1 items-center justify-center text-body text-ink2">Loading</div>;
  let main: React.ReactNode;
  switch (route.name) {
    case 'chat': { const [cid, jump] = route.chatId ? route.chatId.split('#') : [null, null]; main = <ChatScreen chatId={cid ?? null} jumpTo={jump ?? null} />; break; }
    case 'list': main = <ChatListScreen />; break;
    case 'settings': main = <Suspense fallback={fallback}><SettingsScreen section={route.section} /></Suspense>; break;
    case 'memory': main = <Suspense fallback={fallback}><MemoryScreen /></Suspense>; break;
    case 'model': main = <ChatScreen chatId={null} />; break;
  }
  if (wide && route.name !== 'list') {
    return (
      <div className="flex min-h-0 flex-1">
        <aside className="hidden w-[320px] shrink-0 border-r border-rule md:flex md:flex-col"><ChatListScreen /></aside>
        <main className="flex min-h-0 flex-1 flex-col">{main}</main>
      </div>
    );
  }
  if (wide && route.name === 'list') {
    return (
      <div className="flex min-h-0 flex-1">
        <aside className="flex w-[320px] shrink-0 flex-col border-r border-rule"><ChatListScreen /></aside>
        <main className="flex min-h-0 flex-1 flex-col"><ChatScreen chatId={null} /></main>
      </div>
    );
  }
  return <main className="flex min-h-0 flex-1 flex-col">{main}</main>;
}

export default function App() {
  const ready = useInit();
  if (!ready) return <div className="flex flex-1 items-center justify-center text-body text-ink2" />;
  return (
    <>
      <UpdateBar />
      <OfflineBar />
      <BackupBar />
      <Screen />
      <SheetHost />
      <DialogHost />
      <ToastHost />
    </>
  );
}
