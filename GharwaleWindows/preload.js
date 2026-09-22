// The only bridge between the app's pages and the app. Pages can use just these channels.
const { contextBridge, ipcRenderer } = require("electron");

const LISTEN = ["show", "secondary", "react", "hide"];
const SEND = ["overlay:button", "overlay:interactive", "overlay:shape"];
const INVOKE = ["state:get", "prefs:set", "license:activate", "license:deactivate", "onboarding:finish"];

contextBridge.exposeInMainWorld("gw", {
  on: (channel, fn) => {
    if (LISTEN.includes(channel)) ipcRenderer.on(channel, (_e, data) => fn(data));
  },
  send: (channel, data) => {
    if (SEND.includes(channel)) ipcRenderer.send(channel, data);
  },
  invoke: (channel, data) => {
    if (INVOKE.includes(channel)) return ipcRenderer.invoke(channel, data);
    return Promise.reject(new Error(`Blocked channel: ${channel}`));
  },
});
