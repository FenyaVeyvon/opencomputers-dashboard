import { BadRequestException, Injectable } from '@nestjs/common';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { OcTelemetryDto } from './dto/oc-telemetry.dto';

const STALE_AFTER_MS = 15_000;
const MAX_HISTORY_PER_NODE = 300;
const MAX_CHAT = 500;
const CONFIG_FILE = join(process.cwd(), 'data', 'oc-config.json');

export interface OcNodeConfig {
  node: string;
  nodeLabel: string;
  nodeTags: string[];
  owner: string;
  members: string[];
  tick: number;
  telemetryEvery: number;
  configEvery: number;
  onlineEvery: number;
  meEvery: number;
  fluxEvery: number;
  scanRange: number;
  playerTTL: number;
  chatboxName: string;
  maxChat: number;
  maxLocalLog: number;
  maxItems: number;
  topItems: number;
}

interface StoredNodeConfig {
  version: number;
  config: OcNodeConfig;
}

interface ConfigStore {
  nodes: Record<string, StoredNodeConfig>;
}

export interface OcNodeSnapshot {
  receivedAt: number;
  payload: OcTelemetryDto;
}

export interface OcNodeState {
  node: string;
  receivedAt: number;
  payload: OcTelemetryDto;
  history: OcNodeSnapshot[];
}

export interface OcNodeStatus {
  node: string;
  nodeLabel: string;
  nodeTags: string[];
  online: boolean;
  stale: boolean;
  receivedAt: number;
  ageMs: number;
  playersCount: number | null;
  meTotalItems: number | null;
  meTotalStacks: number | null;
  fluxStored: number | null;
  fluxMax: number | null;
  fluxInput: number | null;
  fluxOutput: number | null;
  apiOk: boolean | null;
  configVersion: number;
}

export interface OcChatItem {
  node: string;
  nodeLabel: string;
  receivedAt: number;
  time?: number;
  player?: string;
  uuid?: string;
  message: string;
}

export interface OcPlayerAggregate {
  name: string;
  uuid?: string;
  online: boolean;
  lastSeenAt: number;
  lastSeenAgoMs: number;
  nodes: Array<{
    node: string;
    nodeLabel: string;
    tags: string[];
    online: boolean;
    source?: string;
  }>;
}

@Injectable()
export class OcService {
  private readonly nodes = new Map<string, OcNodeState>();
  private readonly chat: OcChatItem[] = [];
  private configStore: ConfigStore = { nodes: {} };

  constructor() {
    this.loadConfigStore();
  }

  saveTelemetry(payload: OcTelemetryDto) {
    const node = this.normalizeNode(payload?.node);
    const normalizedPayload = { ...payload, node };
    const receivedAt = Date.now();
    const previous = this.nodes.get(node);
    const history = previous?.history ?? [];
    history.push({ receivedAt, payload: normalizedPayload });

    if (history.length > MAX_HISTORY_PER_NODE) {
      history.splice(0, history.length - MAX_HISTORY_PER_NODE);
    }

    this.nodes.set(node, {
      node,
      receivedAt,
      payload: normalizedPayload,
      history,
    });
    this.appendChat(node, normalizedPayload, receivedAt);

    return { ok: true, node, receivedAt };
  }

  getState() {
    return {
      ok: true,
      time: Date.now(),
      nodes: this.getNodes(),
      players: this.getPlayers(),
      chat: [...this.chat],
      items: this.getItems(),
      fluxHistory: this.getFluxHistory(),
    };
  }

  getNodes(): OcNodeStatus[] {
    return [...this.nodes.values()]
      .map((state) => this.toNodeStatus(state))
      .sort((a, b) => a.node.localeCompare(b.node));
  }

  getNode(nodeInput: string) {
    const node = this.normalizeNode(nodeInput);
    const state = this.nodes.get(node);
    if (!state) {
      throw new BadRequestException({ ok: false, error: 'node not found' });
    }

    return {
      ok: true,
      ...state,
      ...this.toNodeStatus(state),
      players: this.getPlayers().filter((player) =>
        player.nodes.some((item) => item.node === node),
      ),
      chat: this.chat.filter((item) => item.node === node),
    };
  }

  getConfig(nodeInput: string | undefined) {
    const node = this.normalizeNode(nodeInput);
    const entry = this.ensureNodeConfig(node);
    return {
      ok: true,
      configVersion: entry.version,
      ...entry.config,
    };
  }

  updateConfig(nodeInput: string, patch: Partial<OcNodeConfig>) {
    const node = this.normalizeNode(nodeInput);
    const entry = this.ensureNodeConfig(node);
    const config = this.mergeConfig(entry.config, patch, node);
    const version = entry.version + 1;
    this.configStore.nodes[node] = { version, config };
    this.saveConfigStore();
    return { ok: true, node, configVersion: version, config };
  }

  resetConfig(nodeInput: string) {
    const node = this.normalizeNode(nodeInput);
    const previous = this.ensureNodeConfig(node);
    const config = this.createDefaultConfig(node);
    const version = previous.version + 1;
    this.configStore.nodes[node] = { version, config };
    this.saveConfigStore();
    return { ok: true, node, configVersion: version, config };
  }

  getHealth() {
    return { ok: true, service: 'oc-telemetry', time: Date.now() };
  }

  private appendChat(
    node: string,
    payload: OcTelemetryDto,
    receivedAt: number,
  ) {
    const nodeLabel =
      payload.nodeLabel ?? this.ensureNodeConfig(node).config.nodeLabel;
    const chatItems = Array.isArray(payload.chat) ? payload.chat : [];

    for (const item of chatItems) {
      if (typeof item === 'string') {
        this.chat.push({ node, nodeLabel, receivedAt, message: item });
      } else if (item && typeof item === 'object') {
        const message = item.message ?? item.text;
        if (message) {
          this.chat.push({
            node,
            nodeLabel,
            receivedAt,
            time: item.time,
            player: item.player,
            uuid: item.uuid,
            message,
          });
        }
      }
    }

    if (this.chat.length > MAX_CHAT) {
      this.chat.splice(0, this.chat.length - MAX_CHAT);
    }
  }

  private getPlayers(): OcPlayerAggregate[] {
    const map = new Map<string, OcPlayerAggregate>();
    const now = Date.now();

    for (const state of this.nodes.values()) {
      const payload = state.payload;
      const nodeLabel =
        payload.nodeLabel ?? this.ensureNodeConfig(state.node).config.nodeLabel;
      const tags =
        payload.nodeTags ?? this.ensureNodeConfig(state.node).config.nodeTags;

      for (const player of payload.players?.list ?? []) {
        const name = player.name;
        if (!name) continue;
        const key = player.uuid ?? name;
        const lastSeenAt =
          state.receivedAt - Math.max(0, player.age ?? 0) * 1000;
        const current = map.get(key) ?? {
          name,
          uuid: player.uuid,
          online: false,
          lastSeenAt,
          lastSeenAgoMs: now - lastSeenAt,
          nodes: [],
        };

        current.online =
          current.online ||
          Boolean(player.online ?? !this.isStale(state.receivedAt));
        current.lastSeenAt = Math.max(current.lastSeenAt, lastSeenAt);
        current.lastSeenAgoMs = now - current.lastSeenAt;
        current.nodes.push({
          node: state.node,
          nodeLabel,
          tags,
          online: Boolean(player.online ?? !this.isStale(state.receivedAt)),
          source: player.source,
        });
        map.set(key, current);
      }
    }

    return [...map.values()].sort((a, b) => a.name.localeCompare(b.name));
  }

  private getItems() {
    return [...this.nodes.values()]
      .flatMap((state) =>
        [
          ...(state.payload.me?.top ?? []),
          ...(state.payload.me?.materials ?? []),
          ...(state.payload.me?.ores ?? []),
        ].map((item) => ({
          node: state.node,
          nodeLabel:
            state.payload.nodeLabel ??
            this.ensureNodeConfig(state.node).config.nodeLabel,
          ...item,
        })),
      )
      .sort((a, b) => (b.count ?? 0) - (a.count ?? 0))
      .slice(0, 80);
  }

  private getFluxHistory() {
    return [...this.nodes.values()].flatMap((state) =>
      state.history.map((item) => ({
        node: state.node,
        receivedAt: item.receivedAt,
        stored: item.payload.flux?.stored ?? null,
        max: item.payload.flux?.max ?? null,
        input: item.payload.flux?.input ?? null,
        output: item.payload.flux?.output ?? null,
      })),
    );
  }

  private toNodeStatus(state: OcNodeState): OcNodeStatus {
    const ageMs = Date.now() - state.receivedAt;
    const stale = this.isStale(state.receivedAt);
    const config = this.ensureNodeConfig(state.node);

    return {
      node: state.node,
      nodeLabel: state.payload.nodeLabel ?? config.config.nodeLabel,
      nodeTags: state.payload.nodeTags ?? config.config.nodeTags,
      online: !stale,
      stale,
      receivedAt: state.receivedAt,
      ageMs,
      playersCount: state.payload.players?.count ?? null,
      meTotalItems: state.payload.me?.totalItems ?? null,
      meTotalStacks: state.payload.me?.totalStacks ?? null,
      fluxStored: state.payload.flux?.stored ?? null,
      fluxMax: state.payload.flux?.max ?? null,
      fluxInput: state.payload.flux?.input ?? null,
      fluxOutput: state.payload.flux?.output ?? null,
      apiOk: state.payload.api?.ok ?? null,
      configVersion: config.version,
    };
  }

  private isStale(receivedAt: number): boolean {
    return Date.now() - receivedAt > STALE_AFTER_MS;
  }

  private normalizeNode(value: unknown): string {
    const node = typeof value === 'string' ? value.trim() : '';
    if (!node)
      throw new BadRequestException({ ok: false, error: 'node is required' });
    return node;
  }

  private createDefaultConfig(node: string): OcNodeConfig {
    return {
      node,
      nodeLabel: node === 'main-base' ? 'Main Base' : node,
      nodeTags: node === 'main-base' ? ['base'] : [],
      owner: 'FenyaVeyvon',
      members: ['ElliEmerald'],
      tick: 0.5,
      telemetryEvery: 1,
      configEvery: 10,
      onlineEvery: 1,
      meEvery: 2,
      fluxEvery: 1,
      scanRange: 64,
      playerTTL: 300,
      chatboxName: '§bEon§7Dash',
      maxChat: 40,
      maxLocalLog: 14,
      maxItems: 500,
      topItems: 12,
    };
  }

  private ensureNodeConfig(node: string): StoredNodeConfig {
    const existing = this.configStore.nodes[node];
    if (existing) {
      const config = {
        ...this.createDefaultConfig(node),
        ...existing.config,
        node,
      };
      existing.config = config;
      return existing;
    }

    const created = { version: 1, config: this.createDefaultConfig(node) };
    this.configStore.nodes[node] = created;
    this.saveConfigStore();
    return created;
  }

  private mergeConfig(
    current: OcNodeConfig,
    patch: Partial<OcNodeConfig>,
    node: string,
  ) {
    const next = { ...current, node };
    const numbers: Array<keyof OcNodeConfig> = [
      'tick',
      'telemetryEvery',
      'configEvery',
      'onlineEvery',
      'meEvery',
      'fluxEvery',
      'scanRange',
      'playerTTL',
      'maxChat',
      'maxLocalLog',
      'maxItems',
      'topItems',
    ];

    for (const key of numbers) {
      const value = patch[key];
      if (typeof value === 'number' && Number.isFinite(value)) {
        (next[key] as number) = value;
      }
    }

    for (const key of ['nodeLabel', 'owner', 'chatboxName'] as const) {
      if (typeof patch[key] === 'string') next[key] = patch[key];
    }

    if (
      Array.isArray(patch.members) &&
      patch.members.every((v) => typeof v === 'string')
    ) {
      next.members = patch.members;
    }
    if (
      Array.isArray(patch.nodeTags) &&
      patch.nodeTags.every((v) => typeof v === 'string')
    ) {
      next.nodeTags = patch.nodeTags;
    }

    return next;
  }

  private loadConfigStore() {
    mkdirSync(dirname(CONFIG_FILE), { recursive: true });
    if (!existsSync(CONFIG_FILE)) {
      this.saveConfigStore();
      return;
    }

    try {
      const parsed = JSON.parse(
        readFileSync(CONFIG_FILE, 'utf8'),
      ) as ConfigStore;
      this.configStore = parsed?.nodes ? parsed : { nodes: {} };
    } catch {
      this.configStore = { nodes: {} };
      this.saveConfigStore();
    }
  }

  private saveConfigStore() {
    mkdirSync(dirname(CONFIG_FILE), { recursive: true });
    writeFileSync(CONFIG_FILE, JSON.stringify(this.configStore, null, 2));
  }
}
