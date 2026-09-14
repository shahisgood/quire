export type Role = 'system' | 'user' | 'assistant';
export type MessageStatus = 'complete' | 'streaming' | 'interrupted' | 'error';

export interface Chat {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  folderId?: string;
  pinned: boolean;
  archived: boolean;
  modelId: string;
  settingsOverride?: Partial<GenerationSettings>;
  systemPromptId?: string;
  systemPromptInline?: string;
  memoryEnabled: boolean;
  tokenEstimate: number;
  totalCostUsd: number;
  activeLeafId?: string | null;
  draft?: string;
  scrollTop?: number;
  lastPreview?: string;
  titleAuto?: boolean;
}

export interface Attachment {
  id: string;
  kind: 'image' | 'file';
  mime: string;
  name: string;
  size: number;
  dataUrl: string;
}

export interface Usage {
  promptTokens: number;
  completionTokens: number;
  reasoningTokens?: number;
  costUsd?: number;
  authoritative?: boolean;
  estimated?: boolean;
  webSearchCostUsd?: number;
}

export interface Message {
  id: string;
  chatId: string;
  parentId: string | null;
  role: Role;
  content: string;
  attachments?: Attachment[];
  reasoning?: string;
  modelId?: string;
  generationId?: string;
  usage?: Usage;
  settingsSnapshot?: GenerationSettings;
  requestSnapshot?: string;
  createdAt: number;
  status: MessageStatus;
  error?: { code: string; message: string; retryAfterMs?: number };
  editedFrom?: string;
  lc?: string;
}

/** OpenRouter's unified effort scale. Providers accept a subset; OpenRouter maps the rest to the nearest they support. */
export type ReasoningEffort = 'none' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh';

export interface ReasoningSettings {
  mode: 'off' | 'effort' | 'budget';
  effort?: ReasoningEffort;
  maxTokens?: number;
  exclude: boolean;
}

export interface ProviderSettings {
  sort?: 'price' | 'throughput' | 'latency';
  order?: string[];
  ignore?: string[];
  allowFallbacks: boolean;
  requireParameters: boolean;
  denyDataCollection: boolean;
}

export interface GenerationSettings {
  temperature?: number;
  topP?: number;
  topK?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  repetitionPenalty?: number;
  minP?: number;
  topA?: number;
  seed?: number;
  maxTokens?: number;
  stop?: string[];
  stream: boolean;
  reasoning?: ReasoningSettings;
  provider?: ProviderSettings;
  webSearch?: { enabled: boolean; maxResults: number };
  transforms?: string[];
  fallbackModels?: string[];
}

export interface Preset {
  id: string;
  name: string;
  systemPrompt: string;
  modelId?: string;
  settings: Partial<GenerationSettings>;
  icon?: string;
  createdAt: number;
}

export type MemoryCategory = 'identity' | 'preference' | 'project' | 'relationship' | 'context';
export const MEMORY_CATEGORIES: MemoryCategory[] = ['identity', 'preference', 'project', 'relationship', 'context'];

export interface MemoryEntry {
  id: string;
  text: string;
  category: MemoryCategory;
  createdAt: number;
  updatedAt: number;
  sourceChatId?: string;
  sourceMessageId?: string;
  pinned: boolean;
  disabled: boolean;
}

export interface Folder { id: string; name: string; createdAt: number; order: number; collapsed?: boolean }

export interface AppSettings {
  apiKey: string | null;
  proxyBaseUrl?: string;
  defaultModelId: string;
  globalSettings: GenerationSettings;
  globalSystemPrompt: string;
  memory: { enabled: boolean; autoExtract: boolean; extractionModelId: string; maxInjectedChars: number };
  ui: {
    theme: 'dark' | 'light' | 'system';
    fontScale: number;
    density: 'comfortable' | 'compact';
    readingFace: 'serif' | 'sans';
    showReasoningByDefault: boolean;
    showCosts: boolean;
    sendOnEnter: boolean;
    hapticsEnabled: boolean;
  };
  lastSyncedModelsAt: number;
  favouriteModelIds: string[];
  recentModelIds: string[];
  lastChatId?: string | null;
  lastExportAt?: number;
  messagesSinceExport?: number;
  persistRequested?: boolean;
  keyMeta?: KeyMeta | null;
  seenModelIds?: string[];
}

export interface KeyMeta {
  label: string;
  usage: number;
  limit: number | null;
  limitRemaining: number | null;
  isFreeTier: boolean;
  rateLimit?: { requests: number; interval: string } | null;
  fetchedAt: number;
}

// ---- OpenRouter models catalogue (normalised) ----
export interface ModelPricing {
  prompt: string;
  completion: string;
  request: string;
  image: string;
  web_search: string;
  internal_reasoning: string;
  input_cache_read?: string;
  input_cache_write?: string;
}

export interface ORModel {
  id: string;
  canonicalSlug: string;
  name: string;
  created: number;
  description: string;
  contextLength: number;
  architecture: {
    modality: string;
    inputModalities: string[];
    outputModalities: string[];
    tokenizer: string;
    instructType: string | null;
  };
  pricing: ModelPricing;
  topProvider: { contextLength: number | null; maxCompletionTokens: number | null; isModerated: boolean };
  supportedParameters: string[];
  perRequestLimits?: unknown;
}

export interface ModelCatalogue { key: 'catalogue'; fetchedAt: number; models: ORModel[] }

export interface DayCost { day: string; costUsd: number; messages: number }
