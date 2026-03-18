if (!window.__vproConsoleWarnFilterInstalled && window.console && typeof window.console.warn === 'function') {
  window.__vproConsoleWarnFilterInstalled = true;

  var vproOriginalConsoleWarn = window.console.warn.bind(window.console);
  var suppressedWarnSnippets = [
    '[shiny] Shared input/output IDs were found',
    '"combine_species-lump_tree": 1 input and 1 output',
    '"hier-hier_tree": 1 input and 1 output',
    'DEPRECATED: This filename doesn\'t follow the convention, use bootstrap-datepicker.en-CA.js instead.',
    'DEPRECATED: The language code "kh" is deprecated and will be removed in 2.0. For Khmer support use "km" instead.',
    'DEPRECATED: The language code "kr" is deprecated and will be removed in 2.0. For korean support use "ko" instead.',
    'DEPRECATED: This language code "rs-latin" is deprecated (invalid serbian language code) and will be removed in 2.0. For Serbian latin support use "sr-latin" instead.',
    'DEPRECATED: This language code "rs" is deprecated (invalid serbian language code) and will be removed in 2.0. For Serbian support use "sr" instead.'
  ];

  window.console.warn = function () {
    var message = Array.prototype.map.call(arguments, function (arg) {
      return typeof arg === 'string' ? arg : String(arg);
    }).join(' ');

    if (suppressedWarnSnippets.some(function (snippet) { return message.indexOf(snippet) !== -1; })) {
      return;
    }

    return vproOriginalConsoleWarn.apply(window.console, arguments);
  };
}

function initializeVproUi() {
  if (window.__vproUiInitialized) {
    return true;
  }
  if (!window.Shiny || typeof Shiny.setInputValue !== 'function' || typeof Shiny.addCustomMessageHandler !== 'function') {
    return false;
  }

  window.__vproUiInitialized = true;

  function shouldIgnoreKey(evt) {
    var tag = (evt.target && evt.target.tagName) ? evt.target.tagName.toLowerCase() : '';
    return tag === 'input' || tag === 'textarea' || evt.target.isContentEditable;
  }

  document.addEventListener('keydown', function (e) {
    var key = (e.key || '').toLowerCase();
    if ((e.ctrlKey || e.metaKey) && key === 's') {
      e.preventDefault();
      Shiny.setInputValue('global_save', Date.now());
      return;
    }
    if ((e.ctrlKey || e.metaKey) && key === 'n') {
      e.preventDefault();
      Shiny.setInputValue('global_new', Date.now());
      return;
    }
    if (shouldIgnoreKey(e)) return;
  });

  var panelWidthStorageKey = 'vpro-floating-panel-width';

  function syncNavbarBridge() {
    var navbar = document.querySelector('.navbar');
    if (!navbar) return;

    var navbarStyles = window.getComputedStyle(navbar);
    var navbarRect = navbar.getBoundingClientRect();
    var rootStyle = document.documentElement.style;

    rootStyle.setProperty('--vpro-navbar-band-height', navbarRect.height + 'px');

    var backgroundImage = navbarStyles.backgroundImage;
    var backgroundColor = navbarStyles.backgroundColor;
    if (backgroundImage && backgroundImage !== 'none') {
      rootStyle.setProperty('--vpro-nav-bridge-color', backgroundImage);
    } else if (backgroundColor && backgroundColor !== 'rgba(0, 0, 0, 0)') {
      rootStyle.setProperty('--vpro-nav-bridge-color', backgroundColor);
    }

    var accentColor = navbarStyles.borderBottomColor;
    if (accentColor && accentColor !== 'rgba(0, 0, 0, 0)') {
      rootStyle.setProperty('--vpro-nav-bridge-accent', accentColor);
    }
  }

  syncNavbarBridge();

  function parsePixelValue(rawValue) {
    var trimmedValue = (rawValue || '').trim();
    if (!trimmedValue) return null;

    if (/^-?\d+(\.\d+)?px$/.test(trimmedValue)) {
      var pixelValue = parseFloat(trimmedValue);
      return Number.isFinite(pixelValue) ? pixelValue : null;
    }

    if (/^-?\d+(\.\d+)?$/.test(trimmedValue)) {
      var bareValue = parseFloat(trimmedValue);
      return Number.isFinite(bareValue) ? bareValue : null;
    }

    var measurementNode = document.createElement('div');
    measurementNode.style.position = 'absolute';
    measurementNode.style.visibility = 'hidden';
    measurementNode.style.pointerEvents = 'none';
    measurementNode.style.width = trimmedValue;
    document.body.appendChild(measurementNode);
    var measuredValue = measurementNode.getBoundingClientRect().width;
    measurementNode.remove();
    return Number.isFinite(measuredValue) && measuredValue > 0 ? measuredValue : null;
  }

  function getPanelBounds() {
    var rootStyles = window.getComputedStyle(document.documentElement);
    var minWidth = parsePixelValue(rootStyles.getPropertyValue('--vpro-panel-min-width')) || 280;
    var maxFromVar = parsePixelValue(rootStyles.getPropertyValue('--vpro-panel-max-width')) || (window.innerWidth - 112);
    var viewportCap = Math.max(minWidth, window.innerWidth - 112);
    var maxWidth = Math.max(minWidth, Math.min(maxFromVar, viewportCap));
    return {
      min: minWidth,
      max: maxWidth
    };
  }

  function clampPanelWidth(width) {
    var bounds = getPanelBounds();
    return Math.min(bounds.max, Math.max(bounds.min, width));
  }

  function applyFloatingPanelWidth(width, persist) {
    if (!Number.isFinite(width)) return;
    var clampedWidth = clampPanelWidth(width);
    document.documentElement.style.setProperty('--vpro-panel-width', clampedWidth + 'px');
    if (persist) {
      try {
        window.localStorage.setItem(panelWidthStorageKey, String(clampedWidth));
      } catch (_err) {
        // Ignore storage failures.
      }
    }
  }

  function restoreFloatingPanelWidth() {
    try {
      var storedWidth = parseFloat(window.localStorage.getItem(panelWidthStorageKey) || '');
      if (Number.isFinite(storedWidth)) {
        applyFloatingPanelWidth(storedWidth, false);
      }
    } catch (_err) {
      // Ignore storage failures.
    }
  }

  restoreFloatingPanelWidth();

  window.addEventListener('resize', function () {
    var currentValue = parsePixelValue(window.getComputedStyle(document.documentElement).getPropertyValue('--vpro-panel-width'));
    if (currentValue !== null) {
      applyFloatingPanelWidth(currentValue, false);
    }

    syncNavbarBridge();
  });

  if (window.ResizeObserver) {
    var navbarBridgeObserver = new window.ResizeObserver(function () {
      syncNavbarBridge();
    });
    var observedNavbar = document.querySelector('.navbar');
    if (observedNavbar) {
      navbarBridgeObserver.observe(observedNavbar);
    }
  }

  window.requestAnimationFrame(function () {
    syncNavbarBridge();
  });

  function startFloatingPanelResize(event) {
    var resizeHandle = closestFromEventTarget(event.target, '.vpro-floating-panel-resize-handle');
    if (!resizeHandle) return;

    var panelWrap = resizeHandle.closest('.vpro-floating-panel-wrap');
    if (!panelWrap) return;

    var startWidth = panelWrap.getBoundingClientRect().width;
    var startX = event.clientX;

    document.body.classList.add('vpro-shell-is-resizing');

    function stopResize() {
      document.body.classList.remove('vpro-shell-is-resizing');
      window.removeEventListener('pointermove', onPointerMove);
      window.removeEventListener('mousemove', onPointerMove);
      window.removeEventListener('pointerup', stopResize);
      window.removeEventListener('mouseup', stopResize);
      window.removeEventListener('pointercancel', stopResize);
    }

    function onPointerMove(moveEvent) {
      var nextWidth = startWidth + (moveEvent.clientX - startX);
      applyFloatingPanelWidth(nextWidth, true);
    }

    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('mousemove', onPointerMove);
    window.addEventListener('pointerup', stopResize, { once: true });
    window.addEventListener('mouseup', stopResize, { once: true });
    window.addEventListener('pointercancel', stopResize, { once: true });
    event.preventDefault();
  }

  document.addEventListener('pointerdown', startFloatingPanelResize);

  document.addEventListener('mousedown', function (event) {
    startFloatingPanelResize(event);
  });

  var dragPayload = null;
  var draggingSidebarItem = false;
  var hierarchyScrollFrame = null;

  function scheduleHierarchyActiveScroll(activeNode) {
    if (hierarchyScrollFrame !== null) {
      window.cancelAnimationFrame(hierarchyScrollFrame);
    }

    hierarchyScrollFrame = window.requestAnimationFrame(function () {
      hierarchyScrollFrame = null;

      var shell = document.querySelector('.vpro-hierarchy-tree-shell');
      if (!shell) return;

      activeNode = activeNode || shell.querySelector('.vpro-hierarchy-node.is-active');
      if (!activeNode) return;

      var shellRect = shell.getBoundingClientRect();
      var nodeRect = activeNode.getBoundingClientRect();
      var outsideTop = nodeRect.top < shellRect.top;
      var outsideBottom = nodeRect.bottom > shellRect.bottom;

      if (outsideTop || outsideBottom) {
        activeNode.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      }
    });
  }

  function setHierarchyActiveSiteUnit(siteUnit, scrollIntoView) {
    var nodes = document.querySelectorAll('.vpro-hierarchy-node.is-site-unit');
    if (!nodes.length) return;

    var selectedNode = null;
    nodes.forEach(function (node) {
      var isMatch = !!siteUnit && (node.dataset.siteUnit || '') === siteUnit;
      node.classList.toggle('is-active', isMatch);
      if (isMatch) {
        selectedNode = node;
      }
    });

    if (selectedNode && scrollIntoView) {
      scheduleHierarchyActiveScroll(selectedNode);
    }
  }

  Shiny.addCustomMessageHandler('hierarchy-sidebar-selection', function (message) {
    var siteUnit = message && message.site_unit ? message.site_unit : '';
    var scrollIntoView = !!(message && message.scroll);
    setHierarchyActiveSiteUnit(siteUnit, scrollIntoView);
  });

  function setHierarchyActiveNode(nodeId, scrollIntoView) {
    var nodes = document.querySelectorAll('.vpro-hierarchy-node.is-hierarchy-node');
    if (!nodes.length) return;

    var selectedNode = null;
    nodes.forEach(function (node) {
      var isMatch = !!nodeId && (node.dataset.hierarchyId || '') === nodeId;
      node.classList.toggle('is-active', isMatch);
      if (isMatch) {
        selectedNode = node;
      }
    });

    if (selectedNode && scrollIntoView) {
      scheduleHierarchyActiveScroll(selectedNode);
    }
  }

  Shiny.addCustomMessageHandler('hierarchy-sidebar-node-selection', function (message) {
    var nodeId = message && message.node_id ? message.node_id : '';
    var scrollIntoView = !!(message && message.scroll);
    setHierarchyActiveNode(nodeId, scrollIntoView);
  });
  
  Shiny.addCustomMessageHandler('vpro-print-window', function (_message) {
    window.setTimeout(function () {
      window.print();
    }, 50);
  });

  function elementFromEventTarget(target) {
    if (!target) return null;
    if (target.nodeType === Node.TEXT_NODE) return target.parentElement;
    return target instanceof Element ? target : null;
  }

  function closestFromEventTarget(target, selector) {
    var element = elementFromEventTarget(target);
    return element ? element.closest(selector) : null;
  }

  function clearDropTargets() {
    document.querySelectorAll('.vpro-hierarchy-drop-target.is-over').forEach(function (node) {
      node.classList.remove('is-over');
    });
  }

  document.addEventListener('dragstart', function (event) {
    var chip = closestFromEventTarget(event.target, '.vpro-hierarchy-plot-chip');
    if (chip) {
      dragPayload = {
        payload_type: 'plot',
        plot_number: chip.dataset.plotNumber || '',
        from_site_unit: chip.dataset.siteUnit || ''
      };
      draggingSidebarItem = true;
      chip.classList.add('is-dragging');

      if (event.dataTransfer) {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', JSON.stringify(dragPayload));
      }
      return;
    }

    var hierarchyHandle = closestFromEventTarget(event.target, '.vpro-hierarchy-drag-handle[data-drag-node-id]');
    if (!hierarchyHandle) return;

    dragPayload = {
      payload_type: 'hierarchy_node',
      node_id: hierarchyHandle.dataset.dragNodeId || '',
      from_parent_id: hierarchyHandle.dataset.dragParentId || ''
    };
    draggingSidebarItem = true;
    hierarchyHandle.classList.add('is-dragging');

    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', JSON.stringify(dragPayload));
    }
  });

  document.addEventListener('dragend', function (event) {
    var chip = closestFromEventTarget(event.target, '.vpro-hierarchy-plot-chip');
    if (chip) chip.classList.remove('is-dragging');
    var hierarchyHandle = closestFromEventTarget(event.target, '.vpro-hierarchy-drag-handle[data-drag-node-id]');
    if (hierarchyHandle) hierarchyHandle.classList.remove('is-dragging');
    clearDropTargets();
    window.setTimeout(function () {
      draggingSidebarItem = false;
      dragPayload = null;
    }, 0);
  });

  document.addEventListener('dragover', function (event) {
    var target = closestFromEventTarget(event.target, '.vpro-hierarchy-drop-target');
    if (!target) return;
    event.preventDefault();
    clearDropTargets();
    target.classList.add('is-over');
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = 'move';
    }
  });

  document.addEventListener('drop', function (event) {
    var target = closestFromEventTarget(event.target, '.vpro-hierarchy-drop-target');
    if (!target) return;
    event.preventDefault();

    var payload = dragPayload;
    if (!payload && event.dataTransfer) {
      try {
        payload = JSON.parse(event.dataTransfer.getData('text/plain') || '{}');
      } catch (err) {
        payload = null;
      }
    }

    clearDropTargets();

    if (!payload || !payload.payload_type) return;

    if (payload.payload_type === 'hierarchy_node') {
      if (!payload.node_id || typeof target.dataset.parentId === 'undefined') return;
      Shiny.setInputValue('hierarchy_sidebar_move_node', {
        node_id: payload.node_id,
        parent_id: target.dataset.parentId || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    if (!payload.plot_number || !target.dataset.siteUnit) return;

    Shiny.setInputValue('hierarchy_sidebar_drop', {
      plot_number: payload.plot_number,
      from_site_unit: payload.from_site_unit || '',
      to_site_unit: target.dataset.siteUnit,
      nonce: Date.now()
    }, { priority: 'event' });
  });

  document.addEventListener('click', function (event) {
    var chip = closestFromEventTarget(event.target, '.vpro-hierarchy-plot-chip');
    if (chip) {
      if (draggingSidebarItem) return;
      Shiny.setInputValue('hierarchy_sidebar_select_plot', {
        plot_number: chip.dataset.plotNumber || '',
        site_unit: chip.dataset.siteUnit || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var hierarchyToggle = closestFromEventTarget(event.target, '.vpro-hierarchy-toggle[data-toggle-node]');
    if (hierarchyToggle) {
      if (draggingSidebarItem) return;
      Shiny.setInputValue('hierarchy_sidebar_toggle_node', {
        node_id: hierarchyToggle.dataset.toggleNode || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var hierarchyTreeNode = closestFromEventTarget(event.target, '.vpro-hierarchy-tree-node[data-open-node]');
    if (hierarchyTreeNode) {
      if (draggingSidebarItem) return;
      Shiny.setInputValue('hierarchy_sidebar_toggle_node', {
        node_id: hierarchyTreeNode.dataset.openNode || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var hierarchyNavTarget = closestFromEventTarget(event.target, '.vpro-hierarchy-nav-target');
    if (hierarchyNavTarget) {
      if (draggingSidebarItem) return;
      Shiny.setInputValue('hierarchy_sidebar_select_node', {
        node_id: hierarchyNavTarget.dataset.openNode || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var hierarchyNode = closestFromEventTarget(event.target, '.vpro-hierarchy-node.is-hierarchy-node');
    if (hierarchyNode) {
      setHierarchyActiveNode(hierarchyNode.dataset.hierarchyId || '', true);
      Shiny.setInputValue('hierarchy_sidebar_select_node', {
        node_id: hierarchyNode.dataset.hierarchyId || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var node = closestFromEventTarget(event.target, '.vpro-hierarchy-node.is-site-unit');
    if (!node) return;
    setHierarchyActiveSiteUnit(node.dataset.siteUnit || '', true);
    Shiny.setInputValue('hierarchy_sidebar_select_site_unit', {
      site_unit: node.dataset.siteUnit || '',
      nonce: Date.now()
    }, { priority: 'event' });
  });

  document.addEventListener('keydown', function (event) {
    var hierarchyToggle = closestFromEventTarget(event.target, '.vpro-hierarchy-toggle[data-toggle-node]');
    if (hierarchyToggle) {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      Shiny.setInputValue('hierarchy_sidebar_toggle_node', {
        node_id: hierarchyToggle.dataset.toggleNode || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var hierarchyTreeNode = closestFromEventTarget(event.target, '.vpro-hierarchy-tree-node[data-open-node]');
    if (hierarchyTreeNode) {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      Shiny.setInputValue('hierarchy_sidebar_toggle_node', {
        node_id: hierarchyTreeNode.dataset.openNode || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var hierarchyNavTarget = closestFromEventTarget(event.target, '.vpro-hierarchy-nav-target');
    if (hierarchyNavTarget) {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      Shiny.setInputValue('hierarchy_sidebar_select_node', {
        node_id: hierarchyNavTarget.dataset.openNode || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var hierarchyNode = closestFromEventTarget(event.target, '.vpro-hierarchy-node.is-hierarchy-node');
    if (hierarchyNode) {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      setHierarchyActiveNode(hierarchyNode.dataset.hierarchyId || '', true);
      Shiny.setInputValue('hierarchy_sidebar_select_node', {
        node_id: hierarchyNode.dataset.hierarchyId || '',
        nonce: Date.now()
      }, { priority: 'event' });
      return;
    }

    var node = closestFromEventTarget(event.target, '.vpro-hierarchy-node.is-site-unit');
    if (!node) return;
    if (event.key !== 'Enter' && event.key !== ' ') return;
    event.preventDefault();
    setHierarchyActiveSiteUnit(node.dataset.siteUnit || '', true);
    Shiny.setInputValue('hierarchy_sidebar_select_site_unit', {
      site_unit: node.dataset.siteUnit || '',
      nonce: Date.now()
    }, { priority: 'event' });
  });

  return true;
}

function bootVproUi(retriesRemaining) {
  if (initializeVproUi()) {
    return;
  }
  if (retriesRemaining <= 0) {
    return;
  }

  window.setTimeout(function () {
    bootVproUi(retriesRemaining - 1);
  }, 50);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', function () {
    bootVproUi(100);
  }, { once: true });
} else {
  bootVproUi(100);
}
