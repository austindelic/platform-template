/** Shared browser/worker protocol for an optional real-time feature. */
export interface ChangeEnvelope<T = unknown> { resourceId: string; revision: number; change: T }
