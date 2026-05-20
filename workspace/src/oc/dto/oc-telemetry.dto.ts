export interface OcPlayer {
  name?: string;
  uuid?: string;
  online?: boolean;
  source?: string;
  node?: string;
  nodeLabel?: string;
  tags?: string[];
  seen?: number;
  lastSeenUptime?: number;
  age?: number;
  exact?: boolean;
}

export interface OcPlayers {
  mode?: string;
  count?: number;
  list?: OcPlayer[];
}

export interface OcComputer {
  energy?: number;
  maxEnergy?: number;
}

export interface OcApi {
  url?: string;
  enabled?: boolean;
  ok?: boolean;
  status?: string;
  lastStatus?: string;
  sent?: number;
  failed?: number;
}

export interface OcChatMessage {
  time?: number;
  text?: string;
  player?: string;
  message?: string;
  uuid?: string;
}

export interface OcMeItem {
  id?: string;
  label?: string;
  count?: number;
}

export interface OcMe {
  ok?: boolean;
  source?: string;
  address?: string;
  storedPower?: number;
  maxPower?: number;
  usage?: number;
  totalStacks?: number;
  totalItems?: number;
  top?: OcMeItem[];
  materials?: OcMeItem[];
  ores?: OcMeItem[];
}

export interface OcFlux {
  ok?: boolean;
  source?: string;
  address?: string;
  stored?: number;
  max?: number;
  input?: number;
  output?: number;
}

export interface OcMeta {
  owner?: string;
  members?: string[];
  components?: number;
  chatbox?: boolean;
  internet?: boolean;
}

export interface OcRemoteConfigStatus {
  url?: string;
  enabled?: boolean;
  ok?: boolean;
  status?: string;
  lastStatus?: string;
  pulled?: number;
  failed?: number;
  version?: number;
  active?: Record<string, unknown>;
}

export interface OcTelemetryDto {
  node: string;
  nodeLabel?: string;
  nodeTags?: string[];
  version?: string;
  uptime?: number;
  computer?: OcComputer;
  api?: OcApi;
  config?: OcRemoteConfigStatus;
  players?: OcPlayers;
  chat?: Array<string | OcChatMessage>;
  logs?: string[];
  me?: OcMe;
  flux?: OcFlux;
  meta?: OcMeta;
  [key: string]: unknown;
}
