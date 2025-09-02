/*
 * Copyright Wazuh
 * SPDX-License-Identifier: Apache-2.0
 */
/**
 * @jest-environment jsdom
 */

describe('client script: server not ready page', () => {
  const ORIGIN = 'http://localhost';

  beforeEach(() => {
    // Fresh DOM root for each test
    document.body.innerHTML = '<div id="root"></div>';

    // Provide required global config consumed at module init
    (window as any).__CONFIG = {
      appName: 'Test App',
      serverBasePath: '/base',
      documentationTroubleshootingLink: 'https://example.com/troubleshooting',
    };

    // JSDOM defaults to http://localhost
    expect(window.location.origin).toBe(ORIGIN);
  });

  afterEach(() => {
    jest.resetModules();
    jest.clearAllMocks();
  });

  function mockFetchReturning(tasks: any[]) {
    const json = async () => ({ message: 'ok', tasks });
    const okResponse = { ok: true, status: 200, statusText: 'OK', json } as any;
    const fetchMock = jest.fn().mockResolvedValue(okResponse);
    (global as any).fetch = fetchMock;
    return fetchMock;
  }

  it('fetches tasks on window load and renders critical/noncritical sections', async () => {
    const sampleTasks = [
      {
        name: 'critical:1',
        status: 'finished',
        result: 'red',
        error: 'Critical error details',
        createdAt: '2024-01-01T00:00:00Z',
        startedAt: '2024-01-01T00:00:00Z',
        finishedAt: '2024-01-01T00:00:05Z',
        duration: 5000,
        _meta: { isCritical: true, isEnabled: true },
      },
      {
        name: 'minor:1',
        status: 'finished',
        result: 'red',
        error: 'Minor error details',
        createdAt: '2024-01-01T00:00:01Z',
        finishedAt: '2024-01-01T00:00:02Z',
        duration: 1000,
        _meta: { isCritical: false, isEnabled: true },
      },
      {
        name: 'ok:1',
        status: 'finished',
        result: 'green',
        _meta: { isCritical: false, isEnabled: true },
      },
    ];

    const fetchMock = mockFetchReturning(sampleTasks);

    // Import script after globals are set so it picks them up at module init
    require('./script.js');

    // Trigger window load handler registered by the script
    window.dispatchEvent(new Event('load'));

    // Allow pending microtasks to flush
    await new Promise((r) => setTimeout(r, 0));

    // Asserts: fetch called with base path + endpoint
    expect(fetchMock).toHaveBeenCalledWith(
      `${ORIGIN}${(window as any).__CONFIG.serverBasePath}/api/healthcheck/internal`,
      expect.objectContaining({ method: 'GET' })
    );

    const root = document.getElementById('root')!;
    expect(root).toBeTruthy();
    expect(root.innerHTML).toContain('Health Check');
    // Documentation link rendered
    expect(root.innerHTML).toContain('Troubleshooting');
    expect(root.querySelector('a[href="https://example.com/troubleshooting"]')).toBeTruthy();

    // Critical and non-critical items are rendered
    expect(root.querySelectorAll('.critical-list .critical-item').length).toBe(1);
    expect(root.querySelectorAll('.noncritical-list .noncritical-item').length).toBe(1);

    // Action buttons present when there are tasks
    expect(document.getElementById('btn-download')).toBeTruthy();
    expect(document.getElementById('btn-run-failed-critical-checks')).toBeTruthy();
  });

  it('clicking "Download checks" triggers a download named healthcheck.json', async () => {
    // Prepare a fake export button in the DOM
    const exportBtn = document.createElement('button');
    exportBtn.id = 'btn-download';
    document.body.appendChild(exportBtn);

    // Stub Blob URL APIs and anchor click (JSDOM doesn't implement these by default)
    (URL as any).createObjectURL = jest.fn(() => 'blob:mock-url');
    (URL as any).revokeObjectURL = jest.fn();
    const createUrlSpy = (URL as any).createObjectURL as jest.Mock;
    const revokeUrlSpy = (URL as any).revokeObjectURL as jest.Mock;
    const clickSpy = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});

    // Intercept appends to capture the anchor element
    const appendedNodes: Element[] = [];
    const appendOriginal = document.body.appendChild.bind(document.body);
    jest.spyOn(document.body, 'appendChild').mockImplementation((node: any) => {
      appendedNodes.push(node);
      return appendOriginal(node);
    });

    // Evaluate the client script in the window context so its functions are globals
    const fs = require('fs');
    const path = require('path');
    const scriptPath = path.resolve(__dirname, './script.js');
    const source = fs.readFileSync(scriptPath, 'utf8');
    (window as any).eval(source);

    // Sanity check: global function is available
    expect(typeof (window as any).downloadHealthChecksAsJSONFile).toBe('function');

    // Invoke the download function directly
    (window as any).downloadHealthChecksAsJSONFile();

    // Anchor element was created, configured and clicked
    const anchor = appendedNodes.find((n) => n.tagName === 'A') as HTMLAnchorElement;
    expect(anchor).toBeTruthy();
    expect(anchor.download).toBe('healthcheck.json');
    expect(anchor.href).toBe('blob:mock-url');
    expect(clickSpy).toHaveBeenCalled();
    expect(createUrlSpy).toHaveBeenCalled();
    expect(revokeUrlSpy).toHaveBeenCalledWith('blob:mock-url');

    // Button gets re-enabled after operation
    expect(exportBtn.disabled).toBe(false);
  });
});
