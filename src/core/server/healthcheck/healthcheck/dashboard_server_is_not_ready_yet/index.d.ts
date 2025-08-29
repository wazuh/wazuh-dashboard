/* eslint-disable @osd/eslint/require-license-header */

declare global {
  namespace Window {
    interface Config {
      appName: string;
      documentationTroubleshootingLink?: string;
      serverBasePath: string;
    }
  }

  interface Window {
    __CONFIG: Window.Config;
  }
}

export {};
