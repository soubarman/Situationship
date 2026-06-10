// ============================================================
// AR Tracker - 20 Snapchat-Style Filters
// Each filter has its own dedicated logic using MediaPipe Face Mesh landmarks
// ============================================================

window.arTracker = {
    canvasCtx: null,
    canvasElement: null,
    faceMesh: null,
    camera: null,
    videoElement: null,
    activeFilter: 'NONE',
    isRunning: false,
    images: {},
    frameCount: 0,

    // ================================================================
    // Per-filter config: scale + offsetX + offsetY
    // scale   → multiplier on faceW for image width
    // offsetX → horizontal shift as fraction of faceW  (+ = right)
    // offsetY → vertical   shift as fraction of faceH  (- = up)
    // These are live-editable from Flutter via updateFilterConfig()
    // ================================================================
    filterConfigs: {
        ThugLife:    { scale: 2.0,  noseScale: 1.0,  offsetX: 0, offsetY: 0     },
        Dog:         { scale: 1.55, noseScale: 0.50,  offsetX: 0, offsetY: -0.42 },
        Cat:         { scale: 1.30, noseScale: 0.45,  offsetX: 0, offsetY: -0.45 },
        Bunny:       { scale: 1.60, noseScale: 1.0,  offsetX: 0, offsetY: 0      },
        Devil:       { scale: 2.00, noseScale: 1.0,  offsetX: 0, offsetY: 0      },
        Angel:       { scale: 1.20, noseScale: 1.0,  offsetX: 0, offsetY: 0      },
        Crown:       { scale: 1.30, noseScale: 1.0,  offsetX: 0, offsetY: 0      },
        FlowerCrown: { scale: 1.80, noseScale: 1.0,  offsetX: 0, offsetY: 0      },
        HeartEyes:   { scale: 2.60, noseScale: 1.0,  offsetX: 0, offsetY: 0      },
        Clown:       { scale: 1.70, noseScale: 0.45,  offsetX: 0, offsetY: 0      },
    },

    // Live-update a filter's config from Flutter (no recompile needed)
    updateFilterConfig: function(filterName, scale, offsetX, offsetY) {
        const key = filterName.replace(/\s/g, '');
        if (!this.filterConfigs[key]) this.filterConfigs[key] = {};
        this.filterConfigs[key].scale   = scale;
        this.filterConfigs[key].offsetX = offsetX;
        this.filterConfigs[key].offsetY = offsetY;
    },

    // Convenience: get config with fallback
    _cfg: function(key) {
        return this.filterConfigs[key] || { scale: 1.0, noseScale: 1.0, offsetX: 0, offsetY: 0 };
    },

    // ---- Filter image assets are now injected by Flutter as base64 strings ----
    loadImages: function() {
        // We no longer pre-load using fetch or Image() because it triggers
        // CORS blocks and canvas tainting on Android WebView.
        // Instead, the Flutter app reads the PNG assets and injects them 
        // directly as base64 data URIs via setFilterImage/setFilter.
        if (!this.images) this.images = {};
    },

    initialize: function(videoElement) {
        if (this.isRunning) this.stop();
        this.videoElement = videoElement;
        this.canvasElement = document.createElement('canvas');
        this.canvasCtx = this.canvasElement.getContext('2d');
        this.loadImages();

        this.faceMesh = new FaceMesh({ locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh/${file}` });
        this.faceMesh.setOptions({ maxNumFaces: 1, refineLandmarks: true, minDetectionConfidence: 0.5, minTrackingConfidence: 0.5 });
        this.faceMesh.onResults(this.onResults.bind(this));

        this.camera = new Camera(this.videoElement, {
            onFrame: async () => { await this.faceMesh.send({ image: this.videoElement }); },
            width: 640, height: 480
        });
        this.camera.start();
        this.isRunning = true;
        return this.canvasElement;
    },

    setFilter: function(filterName) { this.activeFilter = filterName; },
    stop: function() {
        if (this.camera) this.camera.stop();
        if (this.faceMesh) this.faceMesh.close();
        this.isRunning = false;
    },

    // ---- Core helper: get landmark pixel coords ----
    lm: function(landmarks, idx, w, h) {
        return { x: landmarks[idx].x * w, y: landmarks[idx].y * h, z: landmarks[idx].z };
    },

    // ---- Core helper: draw image with rotation + scale anchored at a point ----
    drawOverlay: function(img, cx, cy, width, height, angle) {
        if (!img || !img.complete || img.naturalWidth === 0) return;
        const ctx = this.canvasCtx;
        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(angle);
        ctx.drawImage(img, -width / 2, -height / 2, width, height);
        ctx.restore();
    },

    // ---- Core helper: crop a section of an image and draw it at (cx,cy) ----
    // sx_frac,sy_frac,sw_frac,sh_frac are all 0..1 fractions of the source image size
    drawCrop: function(img, sx_frac, sy_frac, sw_frac, sh_frac, cx, cy, dw, dh, angle) {
        if (!img || !img.complete || img.naturalWidth === 0) return;
        const ctx  = this.canvasCtx;
        const iw   = img.naturalWidth;
        const ih   = img.naturalHeight;
        const sx   = Math.floor(iw * sx_frac);
        const sy   = Math.floor(ih * sy_frac);
        const sw   = Math.floor(iw * sw_frac);
        const sh   = Math.floor(ih * sh_frac);
        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(angle);
        ctx.drawImage(img, sx, sy, sw, sh, -dw / 2, -dh / 2, dw, dh);
        ctx.restore();
    },

    // ---- Helper: get face width and eye angle ----
    getFaceMetrics: function(landmarks, w, h) {
        const leftEye  = this.lm(landmarks, 33,  w, h);
        const rightEye = this.lm(landmarks, 263, w, h);
        const leftEar  = this.lm(landmarks, 234, w, h);
        const rightEar = this.lm(landmarks, 454, w, h);
        const faceW    = Math.hypot(rightEar.x - leftEar.x, rightEar.y - leftEar.y);
        const angle    = Math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x);
        const midEye   = { x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2 };
        const nose     = this.lm(landmarks, 1, w, h);
        const chin     = this.lm(landmarks, 152, w, h);
        const forehead = this.lm(landmarks, 10, w, h);
        const faceH    = Math.hypot(chin.x - forehead.x, chin.y - forehead.y);
        return { leftEye, rightEye, leftEar, rightEar, faceW, faceH, angle, midEye, nose, chin, forehead };
    },

    onResults: function(results) {
        if (!this.canvasCtx || !this.canvasElement) return;
        const img   = results.image;
        const w     = img.width;
        const h     = img.height;
        this.canvasElement.width  = w;
        this.canvasElement.height = h;
        this.frameCount++;

        const ctx = this.canvasCtx;
        ctx.save();
        ctx.clearRect(0, 0, w, h);
        // Mirror for selfie
        ctx.translate(w, 0);
        ctx.scale(-1, 1);
        ctx.drawImage(img, 0, 0, w, h);

        if (results.multiFaceLandmarks && results.multiFaceLandmarks.length > 0 && this.activeFilter !== 'NONE') {
            const lms = results.multiFaceLandmarks[0];
            switch (this.activeFilter) {
                case 'Thug Life':    this.filterThugLife(lms, w, h);     break;
                case 'Dog':          this.filterDog(lms, w, h);           break;
                case 'Cat':          this.filterCat(lms, w, h);           break;
                case 'Bunny':        this.filterBunny(lms, w, h);         break;
                case 'Devil':        this.filterDevil(lms, w, h);         break;
                case 'Angel':        this.filterAngel(lms, w, h);         break;
                case 'Crown':        this.filterCrown(lms, w, h);         break;
                case 'Flower Crown': this.filterFlowerCrown(lms, w, h);   break;
                case 'Heart Eyes':   this.filterHeartEyes(lms, w, h);     break;
                case 'Clown':        this.filterClown(lms, w, h);         break;
                case 'Rainbow':      this.filterRainbow(lms, w, h);       break;
                case 'Fire':         this.filterFire(lms, w, h);          break;
                case 'Cyberpunk':    this.filterCyberpunk(lms, w, h);     break;
                case 'Stars':        this.filterStars(lms, w, h);         break;
                case 'Tears':        this.filterTears(lms, w, h);         break;
                case 'Beard':        this.filterBeard(lms, w, h);         break;
                case 'Sunglasses':   this.filterSunglasses(lms, w, h);    break;
                case 'Neon':         this.filterNeon(lms, w, h);          break;
                case 'Glitter':      this.filterGlitter(lms, w, h);       break;
                case 'Alien':        this.filterAlien(lms, w, h);         break;
            }
        }
        ctx.restore();
    },

    // ================================================================
    // FILTER 1: Thug Life - Pixel glasses tracked to eyes with head tilt
    // ================================================================
    filterThugLife: function(lms, w, h) {
        const m   = this.getFaceMetrics(lms, w, h);
        const cfg = this._cfg('ThugLife');
        const img = this.images.thugLife;
        const eyeDist  = Math.hypot(m.rightEye.x - m.leftEye.x, m.rightEye.y - m.leftEye.y);
        const glassesW = eyeDist * cfg.scale;
        const glassesH = img.complete && img.naturalWidth > 0
            ? glassesW * (img.naturalHeight / img.naturalWidth)
            : glassesW * 0.35;
        const cx = m.midEye.x + m.faceW * cfg.offsetX;
        const cy = m.midEye.y + m.faceH * cfg.offsetY;
        this.drawOverlay(img, cx, cy, glassesW, glassesH, m.angle);
    },

    // ================================================================
    // FILTER 2: Dog - 3 independent sections from the combined PNG:
    //   SECTION A: Top 45% of PNG → ears above forehead
    //   SECTION B: Center 30% of PNG (nose area) → at nose tip
    //   SECTION C: Left/right 35% sides (whiskers) → at cheeks
    // ================================================================
    filterDog: function(lms, w, h) {
        const m    = this.getFaceMetrics(lms, w, h);
        const cfg  = this._cfg('Dog');
        const img  = this.images.dog;
        const nose = this.lm(lms, 4, w, h);

        // SECTION A: Ears — driven by cfg.scale
        const earW  = m.faceW * cfg.scale;
        const earH  = earW * 0.48;
        const earCY = m.forehead.y + m.faceH * cfg.offsetY;
        const earCX = m.midEye.x   + m.faceW * cfg.offsetX;
        this.drawCrop(img, 0, 0, 1, 0.45, earCX, earCY, earW, earH, m.angle);

        // SECTION B: Nose — driven by cfg.noseScale
        const noseW = m.faceW * cfg.noseScale;
        const noseH = noseW * 0.75;
        this.drawCrop(img, 0.28, 0.52, 0.44, 0.32, nose.x, nose.y, noseW, noseH, m.angle);

        // SECTION C: Whiskers — proportional to noseScale
        const lCheek = this.lm(lms, 205, w, h);
        const rCheek = this.lm(lms, 425, w, h);
        const wW     = m.faceW * 0.52;
        const wH     = wW * 0.30;
        this.drawCrop(img, 0,    0.42, 0.35, 0.26, lCheek.x - wW * 0.22, lCheek.y, wW, wH, m.angle);
        this.drawCrop(img, 0.65, 0.42, 0.35, 0.26, rCheek.x + wW * 0.22, rCheek.y, wW, wH, m.angle);
    },

    // ================================================================
    // FILTER 3: Cat - 2 independent sections from combined PNG:
    //   SECTION A: Top 48% of PNG → ears above forehead
    //   SECTION B: Center rows 44-78% → nose + whiskers at nose level
    // ================================================================
    filterCat: function(lms, w, h) {
        const m    = this.getFaceMetrics(lms, w, h);
        const cfg  = this._cfg('Cat');
        const img  = this.images.cat;
        const nose = this.lm(lms, 4, w, h);

        // SECTION A: Ears
        const earW  = m.faceW * cfg.scale;
        const earH  = earW * 0.55;
        const earCY = m.forehead.y + m.faceH * cfg.offsetY;
        const earCX = m.midEye.x   + m.faceW * cfg.offsetX;
        this.drawCrop(img, 0, 0, 1, 0.48, earCX, earCY, earW, earH, m.angle);

        // SECTION B: Nose + whiskers — driven by cfg.noseScale
        const nwW = m.faceW * cfg.noseScale;
        const nwH = nwW * 0.38;
        this.drawCrop(img, 0.06, 0.44, 0.88, 0.36, nose.x + m.faceW * cfg.offsetX, nose.y, nwW, nwH, m.angle);
    },

    // ================================================================
    // FILTER 4: Bunny - Ears-only PNG. Anchor bottom of image to forehead.
    // ================================================================
    filterBunny: function(lms, w, h) {
        const m   = this.getFaceMetrics(lms, w, h);
        const cfg = this._cfg('Bunny');
        const img = this.images.bunny;
        // Virtual forehead: landmark 10 is too low for people with hair
        const vForehead = m.forehead.y - (m.faceH * 0.15);
        const earW = m.faceW * cfg.scale;  // 1.6x
        const earH = img.complete && img.naturalWidth > 0
            ? earW * (img.naturalHeight / img.naturalWidth)
            : earW * 1.8;
        const cx = m.midEye.x + m.faceW * cfg.offsetX;
        // Anchor center so ears float well above actual hair line
        const cy = vForehead - earH * 0.75;
        this.drawOverlay(img, cx, cy, earW, earH, m.angle);
    },

    // ================================================================
    // FILTER 5: Devil - Horns-only PNG above head. Anchor bottom of image to forehead.
    // ================================================================
    filterDevil: function(lms, w, h) {
        const m   = this.getFaceMetrics(lms, w, h);
        const cfg = this._cfg('Devil');
        const img = this.images.devil;
        const vForehead = m.forehead.y - (m.faceH * 0.15);
        const hornW = m.faceW * cfg.scale;  // 2.0x
        const hornH = img.complete && img.naturalWidth > 0
            ? hornW * (img.naturalHeight / img.naturalWidth)
            : hornW * 0.55;
        const cx = m.midEye.x + m.faceW * cfg.offsetX;
        // Bottom of horns image sits at virtual forehead
        const cy = vForehead - hornH * 0.5;
        this.drawOverlay(img, cx, cy, hornW, hornH, m.angle);
    },

    // ================================================================
    // FILTER 6: Angel - Halo ring PNG floating above head. Image-only.
    // ================================================================
    filterAngel: function(lms, w, h) {
        const m   = this.getFaceMetrics(lms, w, h);
        const cfg = this._cfg('Angel');
        const img = this.images.halo;
        const vForehead = m.forehead.y - (m.faceH * 0.15);
        const haloW = m.faceW * cfg.scale;  // 1.2x
        const haloH = img.complete && img.naturalWidth > 0
            ? haloW * (img.naturalHeight / img.naturalWidth)
            : haloW * 0.45;
        const cx = m.midEye.x + m.faceW * cfg.offsetX;
        // Halo floats above virtual forehead
        const cy = vForehead - haloH * 0.6;
        this.drawOverlay(img, cx, cy, haloW, haloH, m.angle);
    },

    // ================================================================
    // FILTER 7: Crown - Crown PNG sits on top of forehead. Image-only.
    // ================================================================
    filterCrown: function(lms, w, h) {
        const m   = this.getFaceMetrics(lms, w, h);
        const cfg = this._cfg('Crown');
        const img = this.images.crown;
        const vForehead = m.forehead.y - (m.faceH * 0.15);
        const crownW = m.faceW * cfg.scale;  // 1.3x
        const crownH = img.complete && img.naturalWidth > 0
            ? crownW * (img.naturalHeight / img.naturalWidth)
            : crownW * 0.5;
        const cx = m.midEye.x + m.faceW * cfg.offsetX;
        // Bottom of crown sits at virtual forehead
        const cy = vForehead - crownH * 0.5;
        this.drawOverlay(img, cx, cy, crownW, crownH, m.angle);
    },

    // ================================================================
    // FILTER 8: Flower Crown - Wide band across forehead. Image-only.
    // ================================================================
    filterFlowerCrown: function(lms, w, h) {
        const m   = this.getFaceMetrics(lms, w, h);
        const cfg = this._cfg('FlowerCrown');
        const img = this.images.flowerCrown;
        const vForehead = m.forehead.y - (m.faceH * 0.15);
        const crowW = m.faceW * cfg.scale;  // 1.8x
        const crowH = img.complete && img.naturalWidth > 0
            ? crowW * (img.naturalHeight / img.naturalWidth)
            : crowW * 0.35;
        const cx = m.midEye.x + m.faceW * cfg.offsetX;
        // Center of band sits at virtual forehead
        const cy = vForehead - crowH * 0.1;
        this.drawOverlay(img, cx, cy, crowW, crowH, m.angle);
    },

    // ================================================================
    // FILTER 9: Heart Eyes - Hearts PNG centered on eye zone. Image-only.
    // ================================================================
    filterHeartEyes: function(lms, w, h) {
        const m   = this.getFaceMetrics(lms, w, h);
        const cfg = this._cfg('HeartEyes');
        const img = this.images.hearts;
        const eyeDist = Math.hypot(m.rightEye.x - m.leftEye.x, m.rightEye.y - m.leftEye.y);
        const heartsW = eyeDist * cfg.scale;
        const heartsH = img.complete && img.naturalWidth > 0
            ? heartsW * (img.naturalHeight / img.naturalWidth)
            : heartsW * 0.5;
        const cx = m.midEye.x + m.faceW * cfg.offsetX;
        const cy = m.midEye.y + m.faceH * cfg.offsetY;
        this.drawOverlay(img, cx, cy, heartsW, heartsH, m.angle);
    },

    // ================================================================
    // FILTER 10: Clown - 2 sections:
    //   SECTION A: Top 55% of PNG (wig) → above forehead
    //   SECTION B: Center nose (40-70% rows, center cols) → on nose tip
    // ================================================================
    filterClown: function(lms, w, h) {
        const m    = this.getFaceMetrics(lms, w, h);
        const cfg  = this._cfg('Clown');
        const img  = this.images.clown;
        const nose = this.lm(lms, 4, w, h);
        const vForehead = m.forehead.y - (m.faceH * 0.15);

        // SECTION A: Wig — driven by cfg.scale, uses virtual forehead
        const wigW  = m.faceW * cfg.scale;
        const wigH  = wigW * 0.65;
        const wigCX = m.midEye.x + m.faceW * cfg.offsetX;
        // Center of wig sits above virtual forehead
        const wigCY = vForehead - wigH * 0.35;
        this.drawCrop(img, 0, 0, 1, 0.55, wigCX, wigCY, wigW, wigH, m.angle);

        // SECTION B: Clown nose — 0.45x = large, visible red ball
        const noseW = m.faceW * cfg.noseScale;  // 0.45
        const noseH = noseW;
        this.drawCrop(img, 0.30, 0.45, 0.40, 0.25, nose.x, nose.y, noseW, noseH, m.angle);
    },

    // ================================================================
    // FILTER 11: Rainbow Vomit - Rainbow streams from mouth, animates
    // ================================================================
    filterRainbow: function(lms, w, h) {
        const ctx   = this.canvasCtx;
        const mouth = this.lm(lms, 13, w, h);
        const chin  = this.lm(lms, 152, w, h);
        const t     = Date.now() / 400;
        const colors = ['#FF0000','#FF7F00','#FFFF00','#00FF00','#0000FF','#8B00FF'];
        const streamLen = h * 0.55;

        for (let i = 0; i < colors.length; i++) {
            ctx.save();
            ctx.translate(mouth.x, mouth.y);
            const wave  = Math.sin(t + i * 0.6) * 15;
            ctx.beginPath();
            ctx.moveTo(wave, 0);
            for (let y = 0; y < streamLen; y += 5) {
                const x = wave + Math.sin(t + y * 0.03 + i * 0.7) * 20;
                ctx.lineTo(x, y);
            }
            ctx.strokeStyle = colors[i];
            ctx.lineWidth   = 8;
            ctx.globalAlpha = 0.85;
            ctx.stroke();
            ctx.restore();
        }
        ctx.globalAlpha = 1;
    },

    // ================================================================
    // FILTER 12: Fire - Flames erupt from top of head
    // ================================================================
    filterFire: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const m   = this.getFaceMetrics(lms, w, h);
        const t   = Date.now() / 300;

        for (let i = 0; i < 12; i++) {
            const offset  = (i - 6) * m.faceW * 0.09;
            const baseX   = m.forehead.x + offset;
            const baseY   = m.forehead.y;
            const flameH  = (0.5 + Math.random() * 0.5) * m.faceH * 0.55;
            const flameW  = m.faceW * 0.09;
            const swayX   = Math.sin(t + i * 0.8) * 15;

            const grad = ctx.createLinearGradient(baseX, baseY, baseX + swayX, baseY - flameH);
            grad.addColorStop(0,   'rgba(255, 200, 0, 0.95)');
            grad.addColorStop(0.3, 'rgba(255, 80,  0, 0.9)');
            grad.addColorStop(0.7, 'rgba(255, 0,   0, 0.6)');
            grad.addColorStop(1,   'rgba(100, 0,   0, 0)');

            ctx.beginPath();
            ctx.moveTo(baseX - flameW, baseY);
            ctx.quadraticCurveTo(baseX + swayX - flameW, baseY - flameH * 0.5, baseX + swayX, baseY - flameH);
            ctx.quadraticCurveTo(baseX + swayX + flameW, baseY - flameH * 0.5, baseX + flameW, baseY);
            ctx.closePath();
            ctx.fillStyle = grad;
            ctx.globalAlpha = 0.85;
            ctx.fill();
        }
        ctx.globalAlpha = 1;
    },

    // ================================================================
    // FILTER 13: Cyberpunk - Neon visor across eyes + scanlines
    // ================================================================
    filterCyberpunk: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const m   = this.getFaceMetrics(lms, w, h);
        const t   = Date.now() / 700;
        const lEar = this.lm(lms, 234, w, h);
        const rEar = this.lm(lms, 454, w, h);
        const eyeTop = this.lm(lms, 159, w, h);
        const eyeBot = this.lm(lms, 374, w, h);
        const visorH = Math.abs(eyeBot.y - eyeTop.y) * 2.5;

        ctx.save();
        ctx.translate(m.midEye.x, m.midEye.y);
        ctx.rotate(m.angle);

        // Visor body
        const vw = m.faceW * 1.15;
        ctx.globalCompositeOperation = 'source-over';
        const visorGrad = ctx.createLinearGradient(-vw/2, -visorH/2, vw/2, visorH/2);
        visorGrad.addColorStop(0,   'rgba(0, 255, 255, 0.15)');
        visorGrad.addColorStop(0.5, 'rgba(0, 180, 255, 0.35)');
        visorGrad.addColorStop(1,   'rgba(0, 255, 255, 0.15)');
        ctx.fillStyle = visorGrad;
        ctx.roundRect(-vw/2, -visorH/2, vw, visorH, visorH/3);
        ctx.fill();

        // Neon border
        ctx.shadowBlur   = 20;
        ctx.shadowColor  = '#00FFFF';
        ctx.strokeStyle  = '#00FFFF';
        ctx.lineWidth    = 3;
        ctx.roundRect(-vw/2, -visorH/2, vw, visorH, visorH/3);
        ctx.stroke();
        ctx.shadowBlur = 0;

        // Moving scan line
        const scanY = -visorH/2 + (Math.sin(t) * 0.5 + 0.5) * visorH;
        ctx.strokeStyle = 'rgba(255, 0, 255, 0.9)';
        ctx.lineWidth   = 2;
        ctx.shadowBlur  = 10;
        ctx.shadowColor = '#FF00FF';
        ctx.beginPath();
        ctx.moveTo(-vw/2, scanY);
        ctx.lineTo(vw/2,  scanY);
        ctx.stroke();
        ctx.restore();
    },

    // ================================================================
    // FILTER 14: Stars & Galaxy - Stars float around face, galaxy tint
    // ================================================================
    filterStars: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const m   = this.getFaceMetrics(lms, w, h);
        const t   = Date.now() / 1000;

        // Galaxy tint over face
        const faceGrad = ctx.createRadialGradient(m.midEye.x, m.midEye.y, 0, m.midEye.x, m.midEye.y, m.faceW * 0.7);
        faceGrad.addColorStop(0, 'rgba(80, 0, 120, 0.25)');
        faceGrad.addColorStop(1, 'rgba(0, 0, 80, 0)');
        ctx.fillStyle = faceGrad;
        ctx.fillRect(0, 0, w, h);

        // Orbiting stars
        const colors = ['#FFFFFF', '#FFD700', '#87CEEB', '#FF69B4', '#98FB98'];
        for (let i = 0; i < 12; i++) {
            const angle  = (i / 12) * Math.PI * 2 + t * (i % 2 === 0 ? 0.5 : -0.3);
            const radius = m.faceW * (0.5 + (i % 3) * 0.12);
            const sx     = m.midEye.x + Math.cos(angle) * radius;
            const sy     = m.midEye.y + Math.sin(angle) * radius * 0.6;
            const size   = 4 + Math.sin(t * 2 + i) * 3;
            ctx.fillStyle = colors[i % colors.length];
            ctx.shadowBlur = 8; ctx.shadowColor = colors[i % colors.length];
            this._drawStar(ctx, sx, sy, size, 5);
        }
        ctx.shadowBlur = 0;
    },

    // ================================================================
    // FILTER 15: Tears of Joy - Sparkly tears stream from eyes
    // ================================================================
    filterTears: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const leftEye  = this.lm(lms, 159, w, h); // top left eye
        const rightEye = this.lm(lms, 386, w, h); // top right eye
        const m   = this.getFaceMetrics(lms, w, h);
        const t   = Date.now() / 600;

        const drawTearStream = (startX, startY) => {
            for (let i = 0; i < 5; i++) {
                const progress = ((t * 0.7 + i * 0.2) % 1);
                const oy = progress * m.faceH * 0.7;
                const ox = Math.sin(t + i * 1.3) * 5;
                const alpha = 1 - progress;
                ctx.fillStyle = `rgba(100, 180, 255, ${alpha * 0.9})`;
                ctx.shadowBlur  = 10;
                ctx.shadowColor = 'rgba(150, 200, 255, 0.8)';
                ctx.beginPath();
                ctx.arc(startX + ox, startY + oy, 4 + i, 0, Math.PI * 2);
                ctx.fill();
                // Sparkle
                if (i % 2 === 0) {
                    ctx.fillStyle = `rgba(200, 230, 255, ${alpha})`;
                    this._drawSparkle(ctx, startX + ox + 8, startY + oy, 5);
                }
            }
        };

        drawTearStream(leftEye.x,  leftEye.y + 5);
        drawTearStream(rightEye.x, rightEye.y + 5);
        ctx.shadowBlur = 0;
    },

    // ================================================================
    // FILTER 16: Beard - Dynamic stylized beard on lower face
    // ================================================================
    filterBeard: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const m   = this.getFaceMetrics(lms, w, h);
        const jawL   = this.lm(lms, 172, w, h);
        const jawR   = this.lm(lms, 397, w, h);
        const chin   = this.lm(lms, 175, w, h);
        const upLip  = this.lm(lms, 13,  w, h);
        const mouthL = this.lm(lms, 61,  w, h);
        const mouthR = this.lm(lms, 291, w, h);

        ctx.save();

        // ---- Beard body (stays tight to jawline, no giant droop) ----
        ctx.fillStyle = '#1a1008';
        ctx.beginPath();
        ctx.moveTo(mouthL.x, mouthL.y);
        // Left jaw curve
        ctx.quadraticCurveTo(jawL.x + 10, jawL.y - 15, jawL.x, jawL.y + 8);
        // Chin tip — reduced droop: 0.08 instead of 0.18
        ctx.quadraticCurveTo(
            chin.x - m.faceW * 0.08, chin.y + m.faceW * 0.08,
            chin.x,                  chin.y + m.faceW * 0.08
        );
        ctx.quadraticCurveTo(
            chin.x + m.faceW * 0.08, chin.y + m.faceW * 0.08,
            jawR.x,                  jawR.y + 8
        );
        // Right jaw curve
        ctx.quadraticCurveTo(jawR.x - 10, jawR.y - 15, mouthR.x, mouthR.y);
        ctx.closePath();
        ctx.fill();

        // ---- Beard hair texture lines ----
        ctx.strokeStyle = 'rgba(80,40,10,0.35)';
        ctx.lineWidth = 1.5;
        const midX = (mouthL.x + mouthR.x) / 2;
        for (let i = -3; i <= 3; i++) {
            const lx = midX + i * m.faceW * 0.06;
            ctx.beginPath();
            ctx.moveTo(lx, chin.y - m.faceW * 0.02);
            ctx.lineTo(lx + i * 2, chin.y + m.faceW * 0.06);
            ctx.stroke();
        }

        // ---- Mustache ----
        const muW = (mouthR.x - mouthL.x) * 0.28;
        const muH = m.faceW * 0.035; // thinner
        ctx.fillStyle = '#1a1008';
        // Left half
        ctx.beginPath();
        ctx.ellipse(
            mouthL.x + (mouthR.x - mouthL.x) * 0.25, upLip.y,
            muW, muH, m.angle - 0.1, 0, Math.PI
        );
        ctx.fill();
        // Right half
        ctx.beginPath();
        ctx.ellipse(
            mouthL.x + (mouthR.x - mouthL.x) * 0.75, upLip.y,
            muW, muH, m.angle + 0.1, 0, Math.PI
        );
        ctx.fill();
        ctx.restore();
    },

    // ================================================================
    // FILTER 17: Sunglasses - Stylish gradient sunglasses
    // ================================================================
    filterSunglasses: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const m   = this.getFaceMetrics(lms, w, h);
        const lEye = this.lm(lms, 33,  w, h);
        const rEye = this.lm(lms, 263, w, h);
        const eyeW = m.faceW * 0.22;
        const eyeH = m.faceW * 0.12;

        ctx.save();
        ctx.translate(m.midEye.x, m.midEye.y);
        ctx.rotate(m.angle);

        // Left lens gradient
        const drawLens = (x, gColor1, gColor2) => {
            const g = ctx.createLinearGradient(x - eyeW, -eyeH, x + eyeW, eyeH);
            g.addColorStop(0, gColor1);
            g.addColorStop(1, gColor2);
            ctx.fillStyle = g;
            ctx.strokeStyle = '#111';
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.roundRect(x - eyeW, -eyeH, eyeW*2, eyeH*2, eyeH * 0.7);
            ctx.fill();
            ctx.stroke();
            // Lens shine
            ctx.fillStyle = 'rgba(255,255,255,0.18)';
            ctx.beginPath();
            ctx.ellipse(x - eyeW*0.2, -eyeH*0.2, eyeW*0.4, eyeH*0.3, -0.5, 0, Math.PI*2);
            ctx.fill();
        };

        const lx = lEye.x - m.midEye.x;
        const rx = rEye.x - m.midEye.x;
        drawLens(lx, 'rgba(100,0,200,0.75)', 'rgba(200,0,100,0.75)');
        drawLens(rx, 'rgba(100,0,200,0.75)', 'rgba(200,0,100,0.75)');

        // Bridge
        ctx.strokeStyle = '#111';
        ctx.lineWidth   = 3;
        ctx.beginPath();
        ctx.moveTo(lx + eyeW, 0);
        ctx.lineTo(rx - eyeW, 0);
        ctx.stroke();

        // Arms
        ctx.beginPath();
        ctx.moveTo(lx - eyeW, 0);
        ctx.lineTo(lx - eyeW - m.faceW * 0.2, m.faceW * 0.05);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(rx + eyeW, 0);
        ctx.lineTo(rx + eyeW + m.faceW * 0.2, m.faceW * 0.05);
        ctx.stroke();
        ctx.restore();
    },

    // ================================================================
    // FILTER 18: Neon - Neon glowing lines trace facial features
    // ================================================================
    filterNeon: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const t   = Date.now() / 1000;
        const neonColors = ['#FF00FF', '#00FFFF', '#FF8800', '#00FF88'];

        const drawNeonLine = (points, color, lw = 3) => {
            if (points.length < 2) return;
            ctx.shadowBlur  = 20;
            ctx.shadowColor = color;
            ctx.strokeStyle = color;
            ctx.lineWidth   = lw;
            ctx.beginPath();
            ctx.moveTo(points[0].x * w, points[0].y * h);
            for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x * w, points[i].y * h);
            ctx.stroke();
            ctx.shadowBlur = 0;
        };

        // Lip outlines
        const c = Math.floor(t * 0.5) % neonColors.length;
        const lipColor = neonColors[c];

        // Upper lip
        const upperLip = [61,185,40,39,37,0,267,269,270,409,291].map(i => lms[i]);
        drawNeonLine(upperLip, lipColor, 4);
        // Lower lip
        const lowerLip = [61,146,91,181,84,17,314,405,321,375,291].map(i => lms[i]);
        drawNeonLine(lowerLip, lipColor, 4);

        // Eye outlines
        const leftEyeIdxs = [33,160,158,133,153,144,33];
        drawNeonLine(leftEyeIdxs.map(i => lms[i]), neonColors[(c+1)%4], 3);
        const rightEyeIdxs = [362,385,387,263,373,380,362];
        drawNeonLine(rightEyeIdxs.map(i => lms[i]), neonColors[(c+1)%4], 3);

        // Glitter dots at corners of eyes
        ctx.fillStyle = '#FFFFFF';
        [[33,0],[133,1],[362,2],[263,3]].forEach(([idx,si]) => {
            const p = lms[idx];
            const s = 4 + Math.sin(t * 3 + si) * 2;
            this._drawSparkle(ctx, p.x*w, p.y*h, s);
        });
    },

    // ================================================================
    // FILTER 19: Glitter - Glitter sparkle particles cover face
    // ================================================================
    filterGlitter: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const m   = this.getFaceMetrics(lms, w, h);
        const t   = Date.now() / 1000;
        const colors = ['#FFD700','#FF69B4','#87CEEB','#98FB98','#DDA0DD','#FF6347'];

        for (let i = 0; i < 50; i++) {
            // Pseudo-random but deterministic per frame group
            const seed  = i * 137.5;
            const angle = (seed % 360) * Math.PI / 180;
            const r     = (seed % 1) * m.faceW * 0.6 + m.faceW * 0.05;
            const px    = m.midEye.x + Math.cos(angle + t * 0.2) * r;
            const py    = m.midEye.y + Math.sin(angle + t * 0.2) * r * 0.8;
            const size  = 3 + Math.sin(t * 4 + i) * 2;
            const alpha = 0.5 + Math.sin(t * 5 + i * 0.7) * 0.4;
            ctx.fillStyle   = colors[i % colors.length];
            ctx.globalAlpha = alpha;
            ctx.shadowBlur  = 6;
            ctx.shadowColor = colors[i % colors.length];
            this._drawSparkle(ctx, px, py, size);
        }
        ctx.globalAlpha = 1;
        ctx.shadowBlur  = 0;
    },

    // ================================================================
    // FILTER 20: Alien - Green skin tint + enlarged black eyes overlay
    // ================================================================
    filterAlien: function(lms, w, h) {
        const ctx = this.canvasCtx;
        const m   = this.getFaceMetrics(lms, w, h);
        const lEye = this.lm(lms, 33,  w, h);
        const rEye = this.lm(lms, 263, w, h);

        // Green skin tint
        const skinGrad = ctx.createRadialGradient(m.midEye.x, m.midEye.y, 0, m.midEye.x, m.midEye.y, m.faceW * 0.7);
        skinGrad.addColorStop(0, 'rgba(0, 200, 80, 0.3)');
        skinGrad.addColorStop(0.7, 'rgba(0, 150, 50, 0.15)');
        skinGrad.addColorStop(1, 'rgba(0, 100, 30, 0)');
        ctx.fillStyle = skinGrad;
        ctx.fillRect(0, 0, w, h);

        // Enlarged alien eyes (black almond shape)
        const drawAlienEye = (cx, cy) => {
            ctx.save();
            ctx.translate(cx, cy);
            ctx.rotate(m.angle);
            const ew = m.faceW * 0.19;
            const eh = m.faceW * 0.14;
            // Eye white (slight)
            ctx.fillStyle = 'rgba(0,20,0,0.85)';
            ctx.beginPath();
            ctx.ellipse(0, 0, ew, eh, 0, 0, Math.PI * 2);
            ctx.fill();
            // Pupil - deep black
            ctx.fillStyle = '#000005';
            ctx.beginPath();
            ctx.ellipse(0, 0, ew*0.5, eh*0.7, 0, 0, Math.PI * 2);
            ctx.fill();
            // Green shine
            ctx.fillStyle = 'rgba(0, 255, 100, 0.4)';
            ctx.beginPath();
            ctx.ellipse(-ew*0.2, -eh*0.25, ew*0.2, eh*0.15, -0.5, 0, Math.PI*2);
            ctx.fill();
            ctx.restore();
        };

        drawAlienEye(lEye.x, lEye.y);
        drawAlienEye(rEye.x, rEye.y);

        // Veins on forehead
        ctx.strokeStyle = 'rgba(0, 160, 60, 0.5)';
        ctx.lineWidth   = 2;
        const forehead  = this.lm(lms, 10, w, h);
        ctx.beginPath();
        ctx.moveTo(forehead.x, forehead.y);
        ctx.quadraticCurveTo(forehead.x - 30, forehead.y + 20, forehead.x - 60, forehead.y + 10);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(forehead.x, forehead.y);
        ctx.quadraticCurveTo(forehead.x + 30, forehead.y + 20, forehead.x + 60, forehead.y + 10);
        ctx.stroke();
    },

    // ================================================================
    // Utility Methods
    // ================================================================
    _drawHeart: function(ctx, cx, cy, size) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.beginPath();
        ctx.moveTo(0, size * 0.3);
        ctx.bezierCurveTo(-size, -size * 0.4, -size * 1.5, size * 0.5, 0, size * 1.2);
        ctx.bezierCurveTo(size * 1.5, size * 0.5, size, -size * 0.4, 0, size * 0.3);
        ctx.fill();
        ctx.restore();
    },

    _drawSparkle: function(ctx, cx, cy, size) {
        ctx.save();
        ctx.translate(cx, cy);
        for (let i = 0; i < 4; i++) {
            ctx.rotate(Math.PI / 4);
            ctx.fillRect(-size * 0.15, -size, size * 0.3, size * 2);
        }
        ctx.restore();
    },

    _drawStar: function(ctx, cx, cy, size, points) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.beginPath();
        for (let i = 0; i < points * 2; i++) {
            const r     = i % 2 === 0 ? size : size * 0.4;
            const angle = (i * Math.PI) / points;
            i === 0 ? ctx.moveTo(r * Math.sin(angle), -r * Math.cos(angle))
                    : ctx.lineTo(r * Math.sin(angle), -r * Math.cos(angle));
        }
        ctx.closePath();
        ctx.fill();
        ctx.restore();
    }
};
