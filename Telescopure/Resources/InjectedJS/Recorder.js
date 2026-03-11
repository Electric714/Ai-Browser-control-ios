(function () {
  const handlers = window.webkit && window.webkit.messageHandlers;

  function log(message) {
    try { handlers.writeLog.postMessage(String(message)); } catch (_) {}
  }

  function cssPath(el) {
    if (!el || el.nodeType !== Node.ELEMENT_NODE) return null;
    if (el.id) return `#${el.id}`;
    const path = [];
    let current = el;
    while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.body) {
      let selector = current.tagName.toLowerCase();
      if (current.classList.length) selector += '.' + Array.from(current.classList).slice(0, 3).join('.');
      const index = Array.from(current.parentNode ? current.parentNode.children : []).indexOf(current);
      selector += `:nth-child(${index + 1})`;
      path.unshift(selector);
      current = current.parentElement;
    }
    return path.join(' > ');
  }

  function payloadFor(el) {
    const dataAttributes = {};
    Array.from(el.attributes || []).forEach(attr => {
      if (attr.name.startsWith('data-')) dataAttributes[attr.name] = attr.value;
    });
    return {
      cssSelector: cssPath(el),
      elementID: el.id || null,
      tagName: (el.tagName || '').toLowerCase(),
      classes: Array.from(el.classList || []),
      ariaLabel: el.getAttribute('aria-label'),
      dataAttributes,
      textSnippet: (el.innerText || el.textContent || '').trim().slice(0, 120),
      siblingIndex: el.parentElement ? Array.from(el.parentElement.children).indexOf(el) : null,
      parentTrail: (function() {
        const trail = [];
        let p = el.parentElement;
        while (p && trail.length < 8) { trail.push((p.tagName || '').toLowerCase()); p = p.parentElement; }
        return trail;
      })(),
      framePath: [],
      shadowHostID: el.getRootNode() instanceof ShadowRoot && el.getRootNode().host ? el.getRootNode().host.id : null,
      outerHTML: (el.outerHTML || '').slice(0, 1000),
      inputValue: 'value' in el ? String(el.value || '') : null
    };
  }

  window.__webPuppetRecording = false;
  window.__webPuppetSetRecording = function(value) {
    window.__webPuppetRecording = !!value;
    log(`recording=${window.__webPuppetRecording}`);
  };

  document.addEventListener('click', function(evt) {
    if (!window.__webPuppetRecording) return;
    const path = evt.composedPath ? evt.composedPath() : [];
    const el = path.find(n => n && n.nodeType === Node.ELEMENT_NODE) || evt.target;
    if (!el) return;
    try {
      handlers.didClickElement.postMessage(payloadFor(el));
    } catch (err) {
      log('capture error ' + err.message);
    }
  }, true);

  function find(locator) {
    if (!locator) return null;
    if (locator.elementID) {
      const byId = document.getElementById(locator.elementID);
      if (byId) return byId;
    }
    if (locator.primaryCSSSelector) {
      const byCss = document.querySelector(locator.primaryCSSSelector);
      if (byCss) return byCss;
    }
    if (locator.tagName && locator.classes && locator.classes.length) {
      const byClass = document.querySelector(`${locator.tagName}.${locator.classes.join('.')}`);
      if (byClass) return byClass;
    }
    if (locator.ariaLabel) {
      const byAria = document.querySelector(`[aria-label="${locator.ariaLabel.replace(/"/g, '\\"')}"]`);
      if (byAria) return byAria;
    }
    if (locator.textSnippet) {
      const nodes = Array.from(document.querySelectorAll(locator.tagName || '*'));
      const byText = nodes.find(n => (n.innerText || '').includes(locator.textSnippet));
      if (byText) return byText;
    }
    return null;
  }

  window.__webPuppetReplay = {
    click(locator) { const el = find(locator); if (el) el.click(); return !!el; },
    typeText(locator, value) {
      const el = find(locator);
      if (!el) return false;
      el.focus();
      el.value = value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    },
    extractText(locator) {
      const el = find(locator);
      return el ? (el.innerText || el.textContent || '').trim() : '';
    }
  };

  log('WebPuppet script loaded');
})();
