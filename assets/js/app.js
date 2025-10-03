// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Import ECharts for wave animation and heatmap
import * as echarts from "echarts"

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
// import {hooks as colocatedHooks} from "phoenix-colocated/evhlegalchat"
const colocatedHooks = {} // Placeholder for colocated hooks
import topbar from "../vendor/topbar"
import mermaid from "mermaid"
import * as THREE from "three"
// React imports
import React from "react"
import { createRoot } from "react-dom/client"
import EntityCalendarHeatmap from "./components/EntityCalendarHeatmap"
// tsParticles loaded via CDN

// Particle Ring System
const MIN_RADIUS = 7.5;
const MAX_RADIUS = 15;
const DEPTH = 2;
const LEFT_COLOR = "6366f1";
const RIGHT_COLOR = "8b5cf6";
const NUM_POINTS = 2500;

/**
 * --- Credit ---
 * https://stackoverflow.com/questions/16360533/calculate-color-hex-having-2-colors-and-percent-position
 */
const getGradientStop = (ratio) => {
    // For outer ring numbers potentially past max radius,
    // just clamp to 0
    ratio = ratio > 1 ? 1 : ratio < 0 ? 0 : ratio;

    const c0 = LEFT_COLOR.match(/.{1,2}/g).map(
    (oct) => parseInt(oct, 16) * (1 - ratio)
    );
    const c1 = RIGHT_COLOR.match(/.{1,2}/g).map(
    (oct) => parseInt(oct, 16) * ratio
    );
    const ci = [0, 1, 2].map((i) => Math.min(Math.round(c0[i] + c1[i]), 255));
    const color = ci
    .reduce((a, v) => (a << 8) + v, 0)
    .toString(16)
    .padStart(6, "0");

    return `#${color}`;
};

const calculateColor = (x) => {
    const maxDiff = MAX_RADIUS * 2;
    const distance = x + MAX_RADIUS;

    const ratio = distance / maxDiff;

    const stop = getGradientStop(ratio);
    return stop;
};

const randomFromInterval = (min, max) => {
    return Math.random() * (max - min) + min;
};

const pointsInner = Array.from(
    { length: NUM_POINTS },
    (v, k) => k + 1
).map((num) => {
    const randomRadius = randomFromInterval(MIN_RADIUS, MAX_RADIUS);
    const randomAngle = Math.random() * Math.PI * 2;

    const x = Math.cos(randomAngle) * randomRadius;
    const y = Math.sin(randomAngle) * randomRadius;
    const z = randomFromInterval(-DEPTH, DEPTH);

    const color = calculateColor(x);

    return {
    idx: num,
    position: [x, y, z],
    color,
    };
});

const pointsOuter = Array.from(
    { length: NUM_POINTS / 4 },
    (v, k) => k + 1
).map((num) => {
    const randomRadius = randomFromInterval(MIN_RADIUS / 2, MAX_RADIUS * 2);
    const angle = Math.random() * Math.PI * 2;

    const x = Math.cos(angle) * randomRadius;
    const y = Math.sin(angle) * randomRadius;
    const z = randomFromInterval(-DEPTH * 10, DEPTH * 10);

    const color = calculateColor(x);

    return {
    idx: num,
    position: [x, y, z],
    color,
    };
});

// Toast Manager Hook
const ToastManager = {
  mounted() {
    this.currentToastTimer = null
    
    this.handleEvent("show_toast", ({type, message, persistent}) => {
      // Clear any existing timer
      if (this.currentToastTimer) {
        clearTimeout(this.currentToastTimer)
        this.currentToastTimer = null
      }
      
      // Only auto-dismiss non-persistent toasts
      if (!persistent) {
        this.currentToastTimer = setTimeout(() => {
          this.pushEvent("dismiss_toast", {})
        }, 5000)
      }
    })
    
    this.handleEvent("clear_persistent_toast", () => {
      // Clear any existing timer when clearing persistent toasts
      if (this.currentToastTimer) {
        clearTimeout(this.currentToastTimer)
        this.currentToastTimer = null
      }
    })
  },
  
  destroyed() {
    if (this.currentToastTimer) {
      clearTimeout(this.currentToastTimer)
    }
  }
}

// Initialize Mermaid (theme based on prefers-color-scheme)
try {
  const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
  mermaid.initialize({ startOnLoad: false, securityLevel: 'loose', theme: prefersDark ? 'dark' : 'default' })
  window.mermaid = mermaid
} catch (_e) {}

// Render all Mermaid diagrams helper (works for static pages and LiveView updates)
function renderAllMermaid() {
  const m = window.mermaid
  if (!m) return
  try {
    if (typeof m.run === "function") {
      m.run({ querySelector: ".mermaid" })
    } else if (typeof m.init === "function") {
      m.init(undefined, document.querySelectorAll(".mermaid"))
    }
  } catch (_e) {}
}

// Run once on initial load (controller-rendered pages won't mount hooks)
document.addEventListener("DOMContentLoaded", () => renderAllMermaid())

// Re-run after LiveView navigations complete
window.addEventListener("phx:page-loading-stop", () => renderAllMermaid())

// Mermaid Hook: initializes diagrams
const Mermaid = {
  mounted() {
    renderAllMermaid()
  },
  updated() {
    renderAllMermaid()
  }
}

// ECharts Tree Hook: initializes tree diagrams
const EChartsTree = {
  mounted() {
    this.initChart()
  },
  updated() {
    this.initChart()
  },
  destroyed() {
    if (this.chart) {
      this.chart.dispose()
    }
  },
  initChart() {
    if (this.chart) {
      this.chart.dispose()
    }
    
    const data = {
      name: 'Legal Entity Management',
      children: [
        {
          name: 'Formation',
          children: [
            {
              name: 'Corporate Structure',
              children: [
                { name: 'Delaware C-Corp', value: 1500 },
                { name: 'LLC Formation', value: 1200 },
                { name: 'Partnership', value: 800 }
              ]
            },
            {
              name: 'Registration',
              children: [
                { name: 'EIN Application', value: 500 },
                { name: 'State Registration', value: 600 },
                { name: 'Foreign Qualification', value: 400 }
              ]
            }
          ]
        },
        {
          name: 'Governance',
          children: [
            {
              name: 'Documentation',
              children: [
                { name: 'Bylaws', value: 900 },
                { name: 'Operating Agreement', value: 1100 },
                { name: 'Board Resolutions', value: 700 }
              ]
            },
            {
              name: 'Compliance',
              children: [
                { name: 'Annual Reports', value: 300 },
                { name: 'Meeting Minutes', value: 400 },
                { name: 'Registered Agent', value: 200 }
              ]
            }
          ]
        },
        {
          name: 'Equity & Finance',
          children: [
            {
              name: 'Cap Table',
              children: [
                { name: 'Founder Equity', value: 2000 },
                { name: 'Employee Stock Options', value: 1500 },
                { name: 'Investor Shares', value: 3000 }
              ]
            },
            {
              name: 'Banking',
              children: [
                { name: 'Business Account', value: 800 },
                { name: 'Credit Facilities', value: 1200 },
                { name: 'Payment Processing', value: 600 }
              ]
            }
          ]
        },
        {
          name: 'Risk Management',
          children: [
            {
              name: 'Insurance',
              children: [
                { name: 'D&O Insurance', value: 500 },
                { name: 'General Liability', value: 400 },
                { name: 'Professional Liability', value: 600 }
              ]
            },
            {
              name: 'Legal Protection',
              children: [
                { name: 'IP Protection', value: 800 },
                { name: 'Contract Management', value: 1000 },
                { name: 'Regulatory Compliance', value: 900 }
              ]
            }
          ]
        }
      ]
    }

    const option = {
      tooltip: {
        trigger: 'item',
        triggerOn: 'mousemove',
        backgroundColor: 'rgba(0, 0, 0, 0.8)',
        borderColor: '#10b981',
        borderWidth: 1,
        textStyle: {
          color: '#fff'
        }
      },
      series: [
        {
          type: 'tree',
          id: 0,
          name: 'legalEntityTree',
          data: [data],
          top: '10%',
          left: '8%',
          bottom: '22%',
          right: '20%',
          symbolSize: 8,
          edgeShape: 'polyline',
          edgeForkPosition: '63%',
          initialTreeDepth: 2,
          lineStyle: {
            width: 2,
            color: '#10b981'
          },
          label: {
            backgroundColor: 'rgba(16, 185, 129, 0.1)',
            borderColor: '#10b981',
            borderWidth: 1,
            borderRadius: 4,
            padding: [4, 8],
            position: 'left',
            verticalAlign: 'middle',
            align: 'right',
            color: '#10b981',
            fontSize: 12
          },
          leaves: {
            label: {
              position: 'right',
              verticalAlign: 'middle',
              align: 'left'
            }
          },
          emphasis: {
            focus: 'descendant'
          },
          expandAndCollapse: true,
          animationDuration: 550,
          animationDurationUpdate: 750
        }
      ]
    }

    this.chart = echarts.init(this.el)
    this.chart.setOption(option)
    
    // Handle resize
    window.addEventListener('resize', () => {
      if (this.chart) {
        this.chart.resize()
      }
    })
  }
}

    // React Hook: mounts React components
    const ReactMount = {
      mounted() {
        console.log('ReactMount hook mounted');
        const componentName = this.el.dataset.reactComponent
        const compact = this.el.dataset.compact === 'true'
        console.log('Component name:', componentName, 'compact:', compact);
        if (componentName === 'EntityCalendarHeatmap') {
          console.log('Creating React root and rendering EntityCalendarHeatmap');
          this.root = createRoot(this.el)
          this.root.render(React.createElement(EntityCalendarHeatmap, { compact }))
        }
      },
      
      destroyed() {
        console.log('ReactMount hook destroyed');
        if (this.root) {
          this.root.unmount()
        }
      }
    }



// LayoutChrome: manages left rail collapse and keyboard shortcuts
const LayoutChrome = {
  mounted() {
    this.grid = this.el
    this.left = this.grid.querySelector('[data-panel="left"]')
    this.toggleLeftBtn = this.grid.querySelector('[data-action="toggle-left"]')

    this.leftCollapsed = false

    const COLS_DEFAULT = 'grid-cols-[260px_minmax(0,1fr)]'
    const COLS_COLLAPSED = 'grid-cols-[72px_minmax(0,1fr)]'

    this._apply = () => {
      // update grid cols
      this.grid.classList.remove(COLS_DEFAULT, COLS_COLLAPSED)
      const cols = this.leftCollapsed
        ? COLS_COLLAPSED
        : COLS_DEFAULT
      this.grid.classList.add(cols)

      // toggle label visibility in left rail
      const toggleLabels = (container, hidden) => {
        if (!container) return
        container.querySelectorAll('[data-collapsible-label]')
          .forEach(el => el.classList.toggle('hidden', hidden))
      }
      toggleLabels(this.left, this.leftCollapsed)
    }

    this.toggleLeft = () => { this.leftCollapsed = !this.leftCollapsed; this._apply() }

    this.toggleLeftBtn?.addEventListener('click', this.toggleLeft)

    this._onKeyDown = (e) => {
      const key = (e.key || '').toLowerCase()
      const mod = e.metaKey || e.ctrlKey
      if (mod && key === 'b') { e.preventDefault(); this.toggleLeft() }
      if (mod && key === 'k') {
        const search = this.grid.querySelector('[data-role="command-search"]')
        if (search) { e.preventDefault(); search.focus() }
      }
    }
    window.addEventListener('keydown', this._onKeyDown)

    this._apply()
  },
  destroyed() {
    window.removeEventListener('keydown', this._onKeyDown)
    this.toggleLeftBtn?.removeEventListener('click', this.toggleLeft)
  }
}

// Global ECharts Noise-based Background (LiveView Hook)
const WaveAnimation = {
  mounted() {
    this.chart = echarts.init(this.el, null, {renderer: "canvas"})

    const getNoiseHelper = () => {
      class Grad {
        constructor(x, y, z) { this.x = x; this.y = y; this.z = z }
        dot2(x, y) { return this.x * x + this.y * y }
        dot3(x, y, z) { return this.x * x + this.y * y + this.z * z }
      }
      const grad3 = [
        new Grad(1, 1, 0), new Grad(-1, 1, 0), new Grad(1, -1, 0), new Grad(-1, -1, 0),
        new Grad(1, 0, 1), new Grad(-1, 0, 1), new Grad(1, 0, -1), new Grad(-1, 0, -1),
        new Grad(0, 1, 1), new Grad(0, -1, 1), new Grad(0, 1, -1), new Grad(0, -1, -1)
      ]
      const p = [151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180]
      let perm = new Array(512)
      let gradP = new Array(512)
      function seed(seed) {
        if (seed > 0 && seed < 1) seed *= 65536
        seed = Math.floor(seed)
        if (seed < 256) seed |= seed << 8
        for (let i = 0; i < 256; i++) {
          let v = (i & 1) ? (p[i] ^ (seed & 255)) : (p[i] ^ ((seed >> 8) & 255))
          perm[i] = perm[i + 256] = v
          gradP[i] = gradP[i + 256] = grad3[v % 12]
        }
      }
      function fade(t) { return t * t * t * (t * (t * 6 - 15) + 10) }
      function lerp(a, b, t) { return (1 - t) * a + t * b }
      function perlin2(x, y) {
        let X = Math.floor(x), Y = Math.floor(y)
        x = x - X; y = y - Y; X = X & 255; Y = Y & 255
        let n00 = gradP[X + perm[Y]].dot2(x, y)
        let n01 = gradP[X + perm[Y + 1]].dot2(x, y - 1)
        let n10 = gradP[X + 1 + perm[Y]].dot2(x - 1, y)
        let n11 = gradP[X + 1 + perm[Y + 1]].dot2(x - 1, y - 1)
        let u = fade(x)
        return lerp(lerp(n00, n10, u), lerp(n01, n11, u), fade(y))
      }
      seed(0)
      return { seed, perlin2 }
    }

    this.noise = getNoiseHelper()
    this.noise.seed(Math.random())
    this.config = {
      frequency: 10,
      offsetX: 0,
      offsetY: 100,
      minSize: 60,
      maxSize: 80,
      duration: 3000,
      color0: getComputedStyle(document.documentElement).getPropertyValue('--wave-color0').trim() || '#0001201',
      color1: getComputedStyle(document.documentElement).getPropertyValue('--wave-color1').trim() || '#000',
      backgroundColor: 'transparent'
    }

    this._createElements = () => {
      const elements = []
      const w = this.chart.getWidth()
      const h = this.chart.getHeight()
      const step = 48
      for (let x = 24; x < w; x += step) {
        for (let y = 24; y < h; y += step) {
          const rand = this.noise.perlin2(
            x / this.config.frequency + this.config.offsetX,
            y / this.config.frequency + this.config.offsetY
          )
          elements.push({
            type: 'circle',
            x,
            y,
            style: { fill: this.config.color1 },
            shape: { r: this.config.maxSize },
            keyframeAnimation: {
              duration: this.config.duration,
              loop: true,
              delay: (rand - 1) * 10000,
              keyframes: [
                { percent: 0.5, easing: 'sinusoidalInOut', style: { fill: this.config.color0 }, scaleX: this.config.minSize / this.config.maxSize, scaleY: this.config.minSize / this.config.maxSize },
                { percent: 1, easing: 'sinusoidalInOut', style: { fill: this.config.color1 }, scaleX: 1, scaleY: 1 }
              ]
            }
          })
        }
      }
      return elements
    }

    this._render = () => {
      this.chart.setOption({
        backgroundColor: this.config.backgroundColor,
        graphic: { elements: this._createElements() }
      }, true)
    }

    this._onResize = () => {
      this.chart?.resize()
      clearTimeout(this._resizeT)
      this._resizeT = setTimeout(() => this._render(), 120)
    }
    window.addEventListener('resize', this._onResize, {passive: true})

    this._io = new IntersectionObserver((e) => {
      if (e[0]?.isIntersecting) this._render()
    }, {threshold: 0.01})
    this._io.observe(this.el)

    // Listen for theme changes to update wave colors
    this._onThemeChange = () => {
      this.config.color0 = getComputedStyle(document.documentElement).getPropertyValue('--wave-color0').trim() || '#0001201'
      this.config.color1 = getComputedStyle(document.documentElement).getPropertyValue('--wave-color1').trim() || '#000'
      this._render()
    }
    
    // Listen for data-theme attribute changes
    this._observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'attributes' && mutation.attributeName === 'data-theme') {
          setTimeout(this._onThemeChange, 50) // Small delay to let CSS variables update
        }
      })
    })
    this._observer.observe(document.documentElement, { attributes: true })

    this._render()
  },

  destroyed() {
    window.removeEventListener('resize', this._onResize)
    this._io?.disconnect()
    this._observer?.disconnect()
    if (this.chart) this.chart.dispose()
  }
}

// Pointer Flashlight (global on/off)
const FlashlightToggle = {
  mounted() {
    this.input = this.el.matches && this.el.matches('input[type="checkbox"]') ? this.el : this.el.querySelector?.('input[type="checkbox"]')
    if (!this.input) return
    const apply = () => {
      const enabled = !!this.input.checked
      document.documentElement.dataset.flashlight = enabled ? 'on' : 'off'
      window.dispatchEvent(new CustomEvent('flashlight:change', { detail: { enabled } }))
    }
    if (!('flashlight' in document.documentElement.dataset)) {
      document.documentElement.dataset.flashlight = this.input.checked ? 'on' : 'off'
    } else {
      this.input.checked = document.documentElement.dataset.flashlight !== 'off'
    }
    this._onChange = () => apply()
    this.input.addEventListener('change', this._onChange)
    apply()
  },
  destroyed() {
    if (this.input && this._onChange) this.input.removeEventListener('change', this._onChange)
  }
}

// Holographic Card Hook (Artifact UI-inspired)
const HolographicCard = {
  mounted() {
    this.rotationFactor = Number(this.el.dataset.rotationFactor || 12)
    this.glowIntensity = Number(this.el.dataset.glowIntensity || 0.8)
    this.holographicIntensity = Number(this.el.dataset.holographicIntensity || 0.4)
    this.prismatic = this.el.dataset.prismatic === 'true'
    this.depth = this.el.dataset.depth === 'true'
    this.glitch = this.el.dataset.glitch === 'true'
    this.tiltEnabled = this.el.dataset.tilt !== 'false' && this.rotationFactor !== 0
    if (this.el.dataset.scanlines === 'true') this.el.classList.add('holo-scanlines')

    this._glitchOffset = {x: 0, y: 0}
    this._hovered = false

    const bg = this.el.dataset.bg || 'rgba(15, 23, 42, 0.75)'
    const bgDark = this.el.dataset.bgDark || 'rgba(15, 23, 42, 0.9)'
    const glowRadius = this.el.dataset.glowRadius || '05%'
    this.el.style.setProperty('--holo-bg', bg)
    this.el.style.setProperty('--holo-bg-dark', bgDark)
    this.el.style.setProperty('--glow-intensity', this.glowIntensity)
    this.el.style.setProperty('--holographic-intensity', this.holographicIntensity)
    this.el.style.setProperty('--holo-glow-radius', glowRadius)
    this.el.style.setProperty('--holo-glow-opacity', '0')
    this.flashlightEnabled = (document.documentElement.dataset.flashlight !== 'off')
    this._onFlashlight = (e) => {
      this.flashlightEnabled = !!(e?.detail?.enabled ?? (document.documentElement.dataset.flashlight !== 'off'))
      if (!this.flashlightEnabled) this.el.style.setProperty('--holo-glow-opacity', '0')
    }
    window.addEventListener('flashlight:change', this._onFlashlight)

    this._onMouseMove = (e) => {
      const rect = this.el.getBoundingClientRect()
      const x = e.clientX - rect.left
      const y = e.clientY - rect.top
      const percentX = x / rect.width
      const percentY = y / rect.height
      this.el.style.setProperty('--mouse-x', `${percentX * 100}%`)
      this.el.style.setProperty('--mouse-y', `${percentY * 100}%`)

      const rotateY = (percentX - 0.5) * this.rotationFactor
      const rotateX = (0.5 - percentY) * this.rotationFactor
      const angle = Math.atan2(y - rect.height / 2, x - rect.width / 2) * (180 / Math.PI)

      if (this.tiltEnabled) {
        const scale = this._hovered ? 1.02 : 1
        const translateZ = this.depth ? (this._hovered ? '50px' : '0px') : '0px'
        const tx = this._glitchOffset.x
        const ty = this._glitchOffset.y
        this.el.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale(${scale}) translateZ(${translateZ}) translate(${tx}px, ${ty}px)`
      }

      if (this.prismatic) {
        // Theme-aware prismatic effect using CSS variables
        const currentTheme = document.documentElement.dataset.theme || 'dark'
        let color1, color2, color3
        
        // Get theme-specific colors
        const styles = getComputedStyle(document.documentElement)
        color1 = styles.getPropertyValue('--emerald-400').trim()
        color2 = styles.getPropertyValue('--emerald-500').trim()
        color3 = styles.getPropertyValue('--emerald-600').trim()
        
        // Create gradient that shifts based on mouse angle but uses theme colors
        const grad = `linear-gradient(${angle}deg, ${color1} 0%, ${color2} 50%, ${color3} 100%)`
        const gradDark = `linear-gradient(${angle}deg, ${color1} 0%, ${color2} 50%, ${color3} 100%)`
        
        this.el.style.setProperty('--holographic-gradient', grad)
        this.el.style.setProperty('--holographic-gradient-dark', gradDark)
      }
    }

    this._onEnter = () => {
      this._hovered = true
      if (this.tiltEnabled) this.el.style.transition = 'transform 0.1s ease-out'
      if (this.flashlightEnabled) this.el.style.setProperty('--holo-glow-opacity', '1')
      if (this.glitch) this._startGlitch()
    }

    this._onLeave = () => {
      this._hovered = false
      this._glitchOffset = {x: 0, y: 0}
      if (this.tiltEnabled) {
        this.el.style.transform = 'perspective(1000px) rotateX(0deg) rotateY(0deg) scale(1) translateZ(0px)'
        this.el.style.transition = 'transform 0.5s ease-out'
      }
      this.el.style.setProperty('--holo-glow-opacity', '0')
      this._stopGlitch()
    }

    this._startGlitch = () => {
      if (this._glitchTimer) return
      this._glitchTimer = setInterval(() => {
        if (!this._hovered) return
        if (Math.random() > 0.92) {
          this._glitchOffset = {x: (Math.random() - 0.5) * 10, y: (Math.random() - 0.5) * 10}
          setTimeout(() => { this._glitchOffset = {x: 0, y: 0} }, 50)
        }
      }, 100)
    }

    this._stopGlitch = () => {
      if (this._glitchTimer) {
        clearInterval(this._glitchTimer)
        this._glitchTimer = null
      }
    }

    this.el.addEventListener('mousemove', this._onMouseMove)
    this.el.addEventListener('mouseenter', this._onEnter)
    this.el.addEventListener('mouseleave', this._onLeave)
  },
  destroyed() {
    this.el.removeEventListener('mousemove', this._onMouseMove)
    this.el.removeEventListener('mouseenter', this._onEnter)
    this.el.removeEventListener('mouseleave', this._onLeave)
    this._stopGlitch()
    window.removeEventListener('flashlight:change', this._onFlashlight)
  }
}

// Theme Toggle Hook (must be defined before LiveSocket is created)
const ThemeToggle = {
  mounted() {
    console.log('ThemeToggle mounted', this.el);
    // Ensure the toggle is a direct child of body to avoid transformed ancestors affecting fixed positioning
    try {
      if (this.el.parentElement !== document.body) {
        document.body.appendChild(this.el)
      }
      // Enforce fixed positioning as a fallback regardless of class changes
      this.el.style.position = 'fixed'
      this.el.style.top = this.el.style.top || '1rem'
      this.el.style.right = this.el.style.right || '1rem'
      this.el.style.zIndex = this.el.style.zIndex || '9999'
    } catch (_e) {}

    this.select = this.el.querySelector('select')
    console.log('Found select element:', this.select);
    if (!this.select) return

    const savedTheme = localStorage.getItem('theme')
    if (savedTheme) {
      document.documentElement.dataset.theme = savedTheme
      document.body.dataset.theme = savedTheme
      this.select.value = savedTheme
    } else {
      // Set initial theme based on html data-theme or default to 'dark'
      const initialTheme = document.documentElement.dataset.theme || 'dark'
      localStorage.setItem('theme', initialTheme)
      document.body.dataset.theme = initialTheme
      this.select.value = initialTheme
    }

    this._onChange = (e) => {
      const newTheme = e.target.value
      console.log('Theme changing to:', newTheme);
      document.documentElement.dataset.theme = newTheme
      document.body.dataset.theme = newTheme
      console.log('HTML element data-theme:', document.documentElement.dataset.theme);
      console.log('Body element data-theme:', document.body.dataset.theme);
      localStorage.setItem('theme', newTheme)
    }
    this.select.addEventListener('change', this._onChange)
  },
  destroyed() {
    if (this.select && this._onChange) this.select.removeEventListener('change', this._onChange)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ToastManager, Mermaid, EChartsTree, WaveAnimation, ReactMount, LayoutChrome, HolographicCard, FlashlightToggle, ThemeToggle},
})


// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

