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
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeVproUi, { once: true });
} else {
  initializeVproUi();
}
