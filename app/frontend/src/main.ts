import { mount } from 'svelte';
import App from './App.svelte';
import { IS_WEB_READONLY } from './web/runtimeMode';
import './tokens.css';
import './vpro.css';
import './styles/workbenches.css';

if (IS_WEB_READONLY) import('./web/webMeta').then((m) => m.mountWeb(mount as never));
else mount(App, { target: document.getElementById('app')! });
