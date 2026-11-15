import { mount } from 'svelte'
import App from './App.svelte'
import './tokens.css'
import './vpro.css'
import './styles/workbenches.css'

mount(App, { target: document.getElementById('app')! })
