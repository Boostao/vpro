if (!window.__vproConsoleWarnFilterInstalled && window.console && typeof window.console.warn === 'function') {
  window.__vproConsoleWarnFilterInstalled = true;

  const vproOriginalConsoleWarn = window.console.warn.bind(window.console);
  const suppressedWarnSnippets = [
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
    const message = Array.prototype.map.call(arguments, function (arg) {
      return typeof arg === 'string' ? arg : String(arg);
    }).join(' ');

    if (suppressedWarnSnippets.some(function (snippet) { return message.indexOf(snippet) !== -1; })) {
      return;
    }

    return vproOriginalConsoleWarn.apply(window.console, arguments);
  };
}