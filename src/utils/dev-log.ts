import { environment } from "@raycast/api";

/** Console methods mirrored in @/utils/dev-log (console.X -> devX). */
export const CONSOLE_METHODS = [
  "log",
  "warn",
  "error",
  "debug",
  "info",
  "table",
  "dir",
  "trace",
  "group",
  "groupCollapsed",
  "groupEnd",
  "time",
  "timeEnd",
  "timeLog",
  "assert",
] as const;

export type ConsoleMethod = (typeof CONSOLE_METHODS)[number];

/** e.g. log -> devLog, warn -> devWarn, groupCollapsed -> devGroupCollapsed */
export function toDevConsoleName(method: ConsoleMethod | string): string {
  return `dev${method.charAt(0).toUpperCase()}${method.slice(1)}`;
}

export function isDevEnvironment(): boolean {
  return environment.isDevelopment;
}

function devOnly<F extends (...args: never[]) => void>(fn: F): F {
  return ((...args: Parameters<F>) => {
    if (environment.isDevelopment) fn(...args);
  }) as F;
}

// console.log -> devLog, console.warn -> devWarn, …
export const devLog = devOnly(console.log.bind(console));
export const devWarn = devOnly(console.warn.bind(console));
export const devError = devOnly(console.error.bind(console));
export const devDebug = devOnly(console.debug.bind(console));
export const devInfo = devOnly(console.info.bind(console));
export const devTable = devOnly(console.table.bind(console));
export const devDir = devOnly(console.dir.bind(console));
export const devTrace = devOnly(console.trace.bind(console));
export const devGroup = devOnly(console.group.bind(console));
export const devGroupCollapsed = devOnly(console.groupCollapsed.bind(console));
export const devGroupEnd = devOnly(console.groupEnd.bind(console));
export const devTime = devOnly(console.time.bind(console));
export const devTimeEnd = devOnly(console.timeEnd.bind(console));
export const devTimeLog = devOnly(console.timeLog.bind(console));
export const devAssert = devOnly(console.assert.bind(console));
