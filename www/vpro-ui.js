function initializeVproUi() {
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

  var dragPayload = null;
  var draggingPlot = false;
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
    if (!chip) return;

    dragPayload = {
      plot_number: chip.dataset.plotNumber || '',
      from_site_unit: chip.dataset.siteUnit || ''
    };
    draggingPlot = true;
    chip.classList.add('is-dragging');

    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', JSON.stringify(dragPayload));
    }
  });

  document.addEventListener('dragend', function (event) {
    var chip = closestFromEventTarget(event.target, '.vpro-hierarchy-plot-chip');
    if (chip) chip.classList.remove('is-dragging');
    clearDropTargets();
    window.setTimeout(function () {
      draggingPlot = false;
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

    if (!payload || !payload.plot_number || !target.dataset.siteUnit) return;

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
      if (draggingPlot) return;
      Shiny.setInputValue('hierarchy_sidebar_select_plot', {
        plot_number: chip.dataset.plotNumber || '',
        site_unit: chip.dataset.siteUnit || '',
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
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeVproUi, { once: true });
} else {
  initializeVproUi();
}
