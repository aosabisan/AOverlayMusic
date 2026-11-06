// ==UserScript==
// @name         AOverlay for Stream Music - browser connector
// @namespace    aoverlay-for-stream-music
// @version      1.4.0
// @author       AOSABI
// @description  Tells AOverlay for Stream Music on this computer which song is playing on Suno, Spotify (web player) or SoundCloud, even when the tab is in the background.
// @match        https://suno.com/*
// @match        https://*.suno.com/*
// @match        https://open.spotify.com/*
// @match        https://soundcloud.com/*
// @match        https://*.soundcloud.com/*
// @grant        GM_xmlhttpRequest
// @grant        GM.xmlHttpRequest
// @connect      localhost
// @connect      127.0.0.1
// @run-at       document-idle
// @noframes
// ==/UserScript==
// Part of AOverlay for Stream Music - made and distributed by AOSABI. See LICENSE.txt.

(function () {
  'use strict';
  var PORT = __PORT__;
  var host = location.hostname;
  var SITE = /suno\.com$/.test(host) ? 'suno' : /spotify\.com$/.test(host) ? 'spotify' : /soundcloud\.com$/.test(host) ? 'soundcloud' : '';
  if (!SITE) return;
  var id = SITE + '-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
  var lastKey = '';
  var lastSent = 0;

  function request(opts) {
    if (typeof GM_xmlhttpRequest === 'function') return GM_xmlhttpRequest(opts);
    if (typeof GM !== 'undefined' && GM && typeof GM.xmlHttpRequest === 'function') return GM.xmlHttpRequest(opts);
  }
  function text(sel, attr) {
    var el = document.querySelector(sel);
    if (!el) return '';
    return String((attr ? el.getAttribute(attr) : el.textContent) || '').trim();
  }

  // Is a song playing? Each site is checked several ways, because sites change their pages.
  function isPlaying() {
    var ms = navigator.mediaSession;
    if (ms && ms.playbackState === 'playing') return true;
    if (ms && ms.playbackState === 'paused') return false;
    var media = Array.prototype.slice.call(document.querySelectorAll('audio, video'));
    var mediaPlaying = media.some(function (m) {
      var src = m.currentSrc || m.src || '';
      return !m.paused && !m.ended && !/\/sil-\d+\.mp3/i.test(src);   // Suno keeps a silent clip around
    });
    if (mediaPlaying) return true;
    if (SITE === 'spotify') {
      var b = document.querySelector('[data-testid="control-button-playpause"]');
      if (b) return /pause/i.test(b.getAttribute('aria-label') || '');
    }
    if (SITE === 'soundcloud') {
      var p = document.querySelector('.playControls__play, .playControl');
      if (p) return /\bplaying\b/.test(p.className);
    }
    return false;
  }

  // The song name and artist: the page's media info first, the player bar as a backup.
  function songInfo() {
    var md = navigator.mediaSession ? navigator.mediaSession.metadata : null;
    var title = md && md.title ? String(md.title) : '';
    var artist = md && md.artist ? String(md.artist) : '';
    if (!title && SITE === 'spotify') {
      title = text('[data-testid="context-item-info-title"]') || text('[data-testid="context-item-link"]');
      artist = artist || text('[data-testid="context-item-info-artist"]');
    }
    if (!title && SITE === 'soundcloud') {
      title = text('.playbackSoundBadge__titleLink', 'title') || text('.playbackSoundBadge__titleLink span:last-child');
      artist = artist || text('.playbackSoundBadge__lightLink', 'title');
    }
    return { title: title, artist: artist };
  }

  function currentState() {
    var info = songInfo();
    return { id: id, site: SITE, playing: isPlaying() && !!info.title, title: info.title, artist: info.artist };
  }

  function send(force, override) {
    var s = override || currentState();
    var key = JSON.stringify(s);
    var now = Date.now();
    if (!force && key === lastKey && now - lastSent < 1500) return;
    lastKey = key;
    lastSent = now;
    try {
      request({
        method: 'POST',
        url: 'http://localhost:' + PORT + '/report',
        data: key,
        headers: { 'Content-Type': 'text/plain' },
        timeout: 2000,
        onerror: function () {},
        ontimeout: function () {}
      });
    } catch (e) {}
  }

  setInterval(function () { send(false); }, 1000);
  ['play', 'playing', 'pause', 'ended', 'emptied', 'loadedmetadata'].forEach(function (ev) {
    document.addEventListener(ev, function () { setTimeout(function () { send(true); }, 100); }, true);
  });
  document.addEventListener('click', function () { setTimeout(function () { send(true); }, 400); }, true);
  window.addEventListener('pagehide', function () {
    send(true, { id: id, site: SITE, playing: false, title: '', artist: '' });
  });
  send(true);
})();
