export interface Fingerprint {
    [key: string]: {
        [key: string]: any;
        $hash?: string;
        lied?: boolean;
    };
}

export async function collectFingerprint(): Promise<Fingerprint> {
    const fingerprint: Fingerprint = {};

    // Collect basic browser information
    fingerprint.navigator = {
        userAgent: navigator.userAgent,
        platform: navigator.platform,
        language: navigator.language,
        languages: navigator.languages,
        hardwareConcurrency: navigator.hardwareConcurrency,
        deviceMemory: (navigator as any).deviceMemory,
        maxTouchPoints: navigator.maxTouchPoints,
    };

    // Collect screen information
    fingerprint.screen = {
        width: screen.width,
        height: screen.height,
        colorDepth: screen.colorDepth,
        pixelDepth: screen.pixelDepth,
        availWidth: screen.availWidth,
        availHeight: screen.availHeight,
    };

    // Collect timezone information
    fingerprint.timezone = {
        offset: new Date().getTimezoneOffset(),
        zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    };

    // Collect WebGL information if available
    try {
        const canvas = document.createElement('canvas');
        const gl = canvas.getContext('webgl');
        if (gl) {
            const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
            if (debugInfo) {
                const vendorParam = debugInfo.UNMASKED_VENDOR_WEBGL;
                const rendererParam = debugInfo.UNMASKED_RENDERER_WEBGL;
                
                if (typeof vendorParam === 'number' && typeof rendererParam === 'number') {
                    fingerprint.webgl = {
                        vendor: gl.getParameter(vendorParam),
                        renderer: gl.getParameter(rendererParam),
                        version: gl.getParameter(gl.VERSION),
                    };
                }
            }
        }
    } catch (e) {
        console.warn('WebGL fingerprint collection failed:', e);
    }

    // Collect canvas fingerprint
    try {
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        if (ctx) {
            canvas.width = 200;
            canvas.height = 200;
            ctx.textBaseline = 'top';
            ctx.font = '14px Arial';
            ctx.textBaseline = 'alphabetic';
            ctx.fillStyle = '#f60';
            ctx.fillRect(125, 1, 62, 20);
            ctx.fillStyle = '#069';
            ctx.fillText('Hello, world!', 2, 15);
            ctx.fillStyle = 'rgba(102, 204, 0, 0.7)';
            ctx.fillText('Hello, world!', 4, 17);
            
            fingerprint.canvas = {
                dataURI: canvas.toDataURL(),
            };
        }
    } catch (e) {
        console.warn('Canvas fingerprint collection failed:', e);
    }

    // Collect audio fingerprint
    try {
        const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
        const oscillator = audioContext.createOscillator();
        const analyser = audioContext.createAnalyser();
        const gainNode = audioContext.createGain();
        const scriptProcessor = audioContext.createScriptProcessor(4096, 1, 1);

        oscillator.connect(analyser);
        analyser.connect(scriptProcessor);
        scriptProcessor.connect(gainNode);
        gainNode.connect(audioContext.destination);

        oscillator.type = 'triangle';
        oscillator.frequency.value = 10000;

        const audioData: number[] = [];
        scriptProcessor.onaudioprocess = (e) => {
            const channelData = e.inputBuffer.getChannelData(0);
            audioData.push(...channelData);
        };

        oscillator.start(0);
        await new Promise(resolve => setTimeout(resolve, 100));
        oscillator.stop();
        audioContext.close();

        fingerprint.audio = {
            data: audioData.slice(0, 1000), // Take first 1000 samples
        };
    } catch (e) {
        console.warn('Audio fingerprint collection failed:', e);
    }

    return fingerprint;
} 