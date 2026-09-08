/*
 * Public browser client for the PMIS Supabase project.
 * The publishable key is intentionally public; do not add a service-role key,
 * database password, Drive token, or other privileged credential here.
 */
(function (global) {
  'use strict';

  const config = Object.freeze({
    url: 'https://bqtgdufbigkbjdtdgeow.supabase.co',
    publishableKey: 'sb_publishable_O8G7c_TgTRWe0ARSNR6p2A_1kFItCKH',
  });

  function assertConfigured() {
    if (!config.url.startsWith('https://') || !config.publishableKey) {
      throw new Error('PMIS backend configuration is incomplete.');
    }
  }

  async function request(path, options) {
    assertConfigured();
    const opts = options || {};
    const headers = new Headers(opts.headers || {});
    headers.set('apikey', config.publishableKey);
    headers.set('Accept', 'application/json');
    if (opts.token) headers.set('Authorization', `Bearer ${opts.token}`);
    if (opts.body !== undefined) headers.set('Content-Type', 'application/json');

    const response = await fetch(`${config.url}${path}`, {
      method: opts.method || 'GET',
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    });
    const body = response.status === 204 ? null : await response.json().catch(() => null);
    if (!response.ok) {
      throw new Error(body && body.message ? body.message : `PMIS backend request failed (${response.status}).`);
    }
    return body;
  }

  global.PMISBackend = Object.freeze({
    config: Object.freeze({ url: config.url }),
    signIn: (email, password) => request('/auth/v1/token?grant_type=password', {
      method: 'POST', body: { email, password },
    }),
    signOut: (token) => request('/auth/v1/logout', { method: 'POST', token }),
    currentUser: (token) => request('/auth/v1/user', { token }),
    projects: (token) => request('/rest/v1/projects?select=id,code,name,starts_on,ends_on,active&order=name.asc', { token }),
    deliverables: (projectId, token) => request(`/rest/v1/deliverables?project_id=eq.${encodeURIComponent(projectId)}&select=*&order=due_on.asc.nullslast`, { token }),
    issues: (projectId, token) => request(`/rest/v1/issues?project_id=eq.${encodeURIComponent(projectId)}&select=*&order=opened_on.desc`, { token }),
  });
})(window);
