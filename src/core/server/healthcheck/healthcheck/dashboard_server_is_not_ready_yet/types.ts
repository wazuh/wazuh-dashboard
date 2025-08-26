/* eslint-disable @osd/eslint/require-license-header */
export type OmitStrict<T, K extends keyof T> = Pick<T, Exclude<keyof T, K>>;

export interface NotReadyServerProps {
  appName: string;
  documentationTroubleshootingLink?: string;
  serverBasePath: string;
}
