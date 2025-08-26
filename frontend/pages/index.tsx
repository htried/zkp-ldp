import Head from 'next/head';
import Script from 'next/script';
import { encode } from 'ngeohash';
import { useEffect, useState } from 'react';
import { collectFingerprint } from '../lib/fingerprint_collector';
import { getFuzzyHash } from '../lib/fuzzy_hash';
import {
  generateCoordinates,
  generateNFingerprints,
  generateNGeohashes,
  generateRandomIPs,
  geohashToIntString,
  hashTo250BitStrings,
  ipToIntString
} from '../lib/utils';
import { UnsignedInput, sign_circom_inputs, verifyStateUpdate } from '../lib/zk_utils';

// Add types for stored state
interface StoredState {
  fingerprintHashes: string[];
  geohashes: string[];
  ipAddresses: string[];
  lastUpdated: number;
}

export default function Home() {
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [fingerprintHashes, setFingerprintHashes] = useState<string[]>([]);
  const [geohashes, setGeohashes] = useState<string[]>([]);
  const [ipAddresses, setIPAddresses] = useState<string[]>([]);
  const [originalState, setOriginalState] = useState<{
    ips: string[];
    geohashes: string[];
    fingerprint: string[] | null;
  }>({
    ips: [],
    geohashes: [],
    fingerprint: null
  });
  const [currentState, setCurrentState] = useState<{
    fingerprint: string[] | null;
    location: { lat: number; lng: number; geohash: string } | null;
    ip: string | null;
  }>({
    fingerprint: null,
    location: null,
    ip: null
  });
  const [options, setOptions] = useState({
    // Client-side configuration
    fingerprintSimilarity: 90, // percentage
    geohashDistance: 0.1, // degrees
    // Server-side configuration
    serverGeohashBits: 20,
    serverFingerprintThreshold: 400
  });
  const [verificationStatus, setVerificationStatus] = useState<string | null>(null);
  const [signatures, setSignatures] = useState<{
    initial_state: { r8x: string; r8y: string; s: string } | null;
    new_user_info: { r8x: string; r8y: string; s: string } | null;
  }>({ initial_state: null, new_user_info: null });
  const [provingTime, setProvingTime] = useState<number | null>(null);
  const [verifyingTime, setVerifyingTime] = useState<number | null>(null);
  const [isParametersExpanded, setIsParametersExpanded] = useState<boolean>(false);
  const [isVerificationInputsExpanded, setIsVerificationInputsExpanded] = useState<boolean>(false);

  const N = 5;

  const geohashConfigs = [
    { bits: 15, label: "3 characters (15 bits, ~156km x ~156km bounding box)" },
    { bits: 20, label: "4 characters (20 bits, ~39km x ~19.5km bounding box)" },
    { bits: 25, label: "5 characters (25 bits, ~5km x ~5km bounding box)" }
  ];

  const fingerprintConfigs = [
    { threshold: 350, label: "Loose (70% similarity)" },
    { threshold: 400, label: "Medium (80% similarity)" },
    { threshold: 450, label: "Strict (90% similarity)" }
  ];

  // Load state from localStorage on component mount and generate initial state
  useEffect(() => {
    const initializeState = async () => {
      try {
        // Generate initial current state
        const fingerprint = await collectFingerprint();
        const fingerprintHash = await getFuzzyHash(fingerprint);
        const [first250, second250] = hashTo250BitStrings(fingerprintHash);
        setCurrentState(prev => ({ ...prev, fingerprint: [first250, second250] }));

        // Using New York City as center point for demo
        const centerLat = 40.7128;
        const centerLng = -74.0060;

        const nearbyPoint = generateCoordinates(centerLat, centerLng, options.geohashDistance);
        const currentGeohash = encode(nearbyPoint.lat, nearbyPoint.lng, 12);
        setCurrentState(prev => ({
          ...prev,
          location: {
            ...nearbyPoint,
            geohash: currentGeohash
          }
        }));

        const currentIP = await fetch('https://api.ipify.org?format=json').then(res => res.json()).then(data => data.ip);
        setCurrentState(prev => ({ ...prev, ip: currentIP }));

        // Check for stored state
        const storedState = localStorage.getItem('zkpState');
        if (storedState) {
          const parsedState: StoredState = JSON.parse(storedState);
          setFingerprintHashes(parsedState.fingerprintHashes);
          setGeohashes(parsedState.geohashes);
          setIPAddresses(parsedState.ipAddresses);
          // setStatus('Historical session data loaded');
        } else {
          // Initialize with default values similar to current state
          const p = (100 - options.fingerprintSimilarity) / 100;
          const hashes = await generateNFingerprints(fingerprint, 1, p);
          setFingerprintHashes(hashes);
          setGeohashes(["0", "0", "0", "0", "0"]);
          setIPAddresses(["0", "0", "0", "0", "0"]);
        }
      } catch (err) {
        console.error('Error initializing state:', err);
        setError(err instanceof Error ? err.message : 'Failed to initialize state');
      }
    };

    initializeState();
  }, []);

  // Save state to localStorage whenever it changes
  useEffect(() => {
    if (fingerprintHashes.length > 0 || geohashes.length > 0 || ipAddresses.length > 0) {
      const stateToStore: StoredState = {
        fingerprintHashes,
        geohashes,
        ipAddresses,
        lastUpdated: Date.now()
      };
      localStorage.setItem('zkpState', JSON.stringify(stateToStore));
    }
  }, [fingerprintHashes, geohashes, ipAddresses]);

  const clearStoredData = () => {
    // Generate new default values similar to current state
    const generateDefaults = async () => {
      try {
        const fingerprint = await collectFingerprint();
        const p = (100 - options.fingerprintSimilarity) / 100;
        const hashes = await generateNFingerprints(fingerprint, 1, p);
        setFingerprintHashes(hashes);
        setGeohashes(["0", "0", "0", "0", "0"]);
        setIPAddresses(["0", "0", "0", "0", "0"]);
        localStorage.removeItem('zkpState');
      } catch (err) {
        console.error('Error generating defaults:', err);
        setError(err instanceof Error ? err.message : 'Failed to generate defaults');
      }
    };

    generateDefaults();
  };

  const updateStoredState = (newFingerprint: string[], newGeohash: string, newIP: string) => {
    // Add new data at the beginning and remove oldest
    setFingerprintHashes(prev => {
      const updated = [newFingerprint.join(',')];
      return updated.slice(0, N);
    });
    setGeohashes(prev => {
      const updated = [`${currentState.location?.lat.toFixed(6)},${currentState.location?.lng.toFixed(6)} (${newGeohash})`, ...prev];
      return updated.slice(0, N);
    });
    setIPAddresses(prev => {
      const updated = [newIP, ...prev];
      return updated.slice(0, N);
    });
  };

  const handleSubmit = async () => {
    setLoading(true);
    setError(null);
    try {
      // setStatus('Generating credential history...');
      const p = (100 - options.fingerprintSimilarity) / 100;
      const fingerprint = await collectFingerprint();
      const hashes = await generateNFingerprints(
        fingerprint,
        1,
        p
      );
      setFingerprintHashes(hashes);

      // Using New York City as center point for demo
      const centerLat = 40.7128;
      const centerLng = -74.0060;

      const geoHashes = await generateNGeohashes(centerLat, centerLng, N, options.geohashDistance);
      setGeohashes(geoHashes);

      const ips = await generateRandomIPs(N, false);
      setIPAddresses(ips);

      // setStatus('Credential history generated successfully');
    } catch (err) {
      console.error('Error:', err);
      setError(err instanceof Error ? err.message : 'Failed to generate data');
    } finally {
      setLoading(false);
    }
  };

  const handleVerify = async () => {
    if (!currentState.fingerprint || !currentState.location || !currentState.ip) {
      setVerificationStatus('Missing required data for verification');
      return;
    }

    setVerificationStatus('Verifying...');
    try {
      const startTime = performance.now();

      // Store original state before verification
      setOriginalState({
        ips: [...ipAddresses],
        geohashes: [...geohashes],
        fingerprint: currentState.fingerprint
      });

      // Set the correct circuit files based on server configuration
      const circuitPath = `/gh_${options.serverGeohashBits}_fp_${options.serverFingerprintThreshold}`;

      // Extract just the geohash part from the formatted strings
      const cleanGeohashes = geohashes.length > 0 ? geohashes.map(hash => {
        const match = hash.match(/\((.*?)\)/);
        return match ? match[1] : hash;
      }) : ["0", "0", "0", "0", "0"];
      const cleanNewGeohash = currentState.location.geohash;

      // Log detailed prefix information
      const input: UnsignedInput = {
        ips: ipAddresses.length > 0 ? ipAddresses.map(ipToIntString) : ["0", "0", "0", "0", "0"],
        geohashes: cleanGeohashes.map(geohashToIntString),
        last_fingerprint: currentState.fingerprint,
        users_prf_seed: "1111111111",
        state_counter: "0",
        initial_comm_rand: "111111111",
        new_ip: ipToIntString(currentState.ip),
        new_geohash: geohashToIntString(cleanNewGeohash),
        new_rappor_nonce: "111111111",
        state_comm_randomness: "111111111",
        new_fingerprint: fingerprintHashes[0] ? fingerprintHashes[0].split(',') : ["0", "0"],
        initial_state_r8x: "",
        initial_state_r8y: "",
        initial_state_s: "",
        new_user_info_r8x: "",
        new_user_info_r8y: "",
        new_user_info_s: ""
      };

      // Sign the input data first to get the signatures
      const signedInput = await sign_circom_inputs(input);

      // Update signatures regardless of verification result
      setSignatures({
        initial_state: {
          r8x: signedInput.initial_state_r8x || "Not available",
          r8y: signedInput.initial_state_r8y || "Not available",
          s: signedInput.initial_state_s || "Not available"
        },
        new_user_info: {
          r8x: signedInput.new_user_info_r8x || "Not available",
          r8y: signedInput.new_user_info_r8y || "Not available",
          s: signedInput.new_user_info_s || "Not available"
        }
      });

      const provingEndTime = performance.now();
      setProvingTime(provingEndTime - startTime);

      // Now verify the state update
      const verifyStartTime = performance.now();
      const isValid = await verifyStateUpdate(signedInput, circuitPath);
      const verifyEndTime = performance.now();
      setVerifyingTime(verifyEndTime - verifyStartTime);

      setVerificationStatus(isValid ? 'Verification successful!' : 'Verification failed');

      // If verification is successful, update the stored state
      if (isValid) {
        updateStoredState(
          currentState.fingerprint,
          currentState.location.geohash,
          currentState.ip
        );
      }
    } catch (err) {
      console.error('Verification error:', err);
      setVerificationStatus('Verification error: ' + (err instanceof Error ? err.message : 'Unknown error'));
    }
  };

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      <Head>
        <title>Zero-Knowledge Credential Generator</title>
        <link rel="icon" href="/favicon.ico" />
      </Head>
      <Script src="https://cdn.jsdelivr.net/npm/snarkjs@0.7.5/build/snarkjs.min.js" strategy="beforeInteractive" />

      <div className="container py-5">
        <h1 className="text-3xl font-bold mb-4">Zero-Knowledge Credential Generator</h1>

        <div className="mb-4">
          <h2 className="text-xl font-semibold mb-2">Your current state</h2>
          <div className="list-group mb-4">
            <div className="list-group-item bg-gray-800 text-white">
              <strong>Current fingerprint</strong>
              <p className="text-sm text-gray-400">A 500-bit <a href='https://en.wikipedia.org/wiki/Fuzzy_hashing' target='_blank' rel='noopener noreferrer' className="orange-link">fuzzy hash</a> of the client's browser characteristics</p>
              {currentState.fingerprint ?
                currentState.fingerprint.map((bits, i) => (
                  <>
                    <code key={i} className="font-mono text-sm break-all mt-1">
                      {bits}
                    </code>
                    <br />
                  </>
                )) : 'Not generated yet'}
            </div>
            <div className="list-group-item bg-gray-800 text-white">
              <strong>Current location and geohash</strong>
              <p className="text-sm text-gray-400">The client's current location encoded as a <a href='https://en.wikipedia.org/wiki/Geohash' target='_blank' rel='noopener noreferrer' className="orange-link">geohash</a> (hardcoded to a random point near NYC for demo)</p>
              {currentState.location ?
                <div>
                  <div><code className="font-mono text-sm">Lat/Lng: {currentState.location.lat.toFixed(6)},{currentState.location.lng.toFixed(6)}</code></div>
                  <div><code className="font-mono text-sm">Geohash: {currentState.location.geohash}</code></div>
                </div> :
                'Not generated yet'}
            </div>
            <div className="list-group-item bg-gray-800 text-white">
              <strong>Current IP address</strong>
              <p className="text-sm text-gray-400">The client's current IP address (used for location verification)</p>
              {currentState.ip ?
                <div><code className='font-mono text-sm'>{currentState.ip}</code></div> :
                'Not generated yet'}
            </div>
          </div>
        </div>

        <div className="flex flex-row items-center space-x-12 mb-4">
          <button
            onClick={handleVerify}
            className="btn btn-primary"
          >
            Verify and add current state to history
          </button>

          <button
            onClick={clearStoredData}
            className="btn btn-secondary"
          >
            Clear History
          </button>
        </div>

        {error && (
          <div className="alert alert-danger mb-4">
            <strong>Error:</strong> {error}
          </div>
        )}

        <div className="row">
          <div className="col-12 mb-4">
            <h2 className="text-2xl font-bold mb-2">Your zero-knowledge credential history</h2>
          </div>

          <div className="col-md-4 mb-4">
            <h3 className="text-xl font-semibold mb-2">Last fingerprint hash</h3>
            <div className="list-group">
              {fingerprintHashes.map((hash, i) => {
                const [first250, second250] = hash.split(',');
                return (
                  <div key={i} className="list-group-item bg-gray-800 text-white">
                    <code className="font-mono text-sm">{first250}<br /></code>
                    <code className="font-mono text-sm">{second250}</code>
                  </div>
                );
              })}
            </div>
          </div>

          <div className="col-md-4 mb-4">
            <h3 className="text-xl font-semibold mb-2">Geohash history</h3>
            <div className="list-group">
              {geohashes.map((hash, i) => (
                <div key={i} className="list-group-item bg-gray-800 text-white">
                  <code className="font-mono text-sm">{hash}</code>
                </div>
              ))}
            </div>
          </div>

          <div className="col-md-4 mb-4">
            <h3 className="text-xl font-semibold mb-2">IP address history</h3>
            <div className="list-group">
              {ipAddresses.map((ip, i) => (
                <div key={i} className="list-group-item bg-gray-800 text-white">
                  <code className="font-mono text-sm">{ip}</code>
                </div>
              ))}
            </div>
          </div>

          <div className="mb-6">
            <div
              onClick={() => setIsParametersExpanded(!isParametersExpanded)}
              className="cursor-pointer bg-gray-800 rounded px-4 py-3 hover:bg-gray-700 transition-colors select-none"
              role="button"
              tabIndex={0}
              aria-expanded={isParametersExpanded}
            >
              <div className="flex items-center">
                <h5 className="text-white text-lg font-semibold m-0 p-0 leading-tight">
                  Try other client history parameters
                </h5>
                <svg
                  className={`chevron-icon ml-2 align-middle transition-transform duration-200 ${isParametersExpanded ? 'rotate-180' : ''} text-white`}
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  style={{ display: 'inline-block', verticalAlign: 'middle' }}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
                </svg>
              </div>
            </div>
            {isParametersExpanded && (
              <div className="bg-gray-800 rounded-b px-4 pb-4 pt-2">
                <p className="mb-2">These parameters control how the theoretical historical state data that the client's current state is going to be compared to is generated:</p>
                <ul className="list-disc pl-4 space-y-2">
                  <li><strong>Fingerprint similarity:</strong> Controls how similar the generated fingerprint is to the client's current one (0-100%)</li>
                  <li><strong>Geohash distance:</strong> Controls how far the generated location is from the client's current one (0-2°). For reference, 0.1° is approximately 8km, 0.5° is approximately 40km, and 1° is approximately 80km at 40° latitude (near NYC).</li>
                </ul>

                <div className="row mt-4">
                  <div className="col-md-6 mb-3">
                    <label className="form-label">Fingerprint similarity (%)</label>
                    <div className="flex items-center">
                      <input
                        type="range"
                        min="0"
                        max="100"
                        value={options.fingerprintSimilarity}
                        onChange={(e) => setOptions({ ...options, fingerprintSimilarity: parseInt(e.target.value) })}
                        className="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer"
                      />
                      <span className="ml-2 w-16 text-center">{options.fingerprintSimilarity}%</span>
                    </div>
                  </div>
                  <div className="col-md-6 mb-3">
                    <label className="form-label">Geohash distance (degrees)</label>
                    <div className="flex items-center">
                      <input
                        type="range"
                        min="0"
                        max="2"
                        step="0.05"
                        value={options.geohashDistance}
                        onChange={(e) => setOptions({ ...options, geohashDistance: parseFloat(e.target.value) })}
                        className="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer"
                      />
                      <span className="ml-2 w-16 text-center">{options.geohashDistance}°</span>
                    </div>
                  </div>
                </div>

                <div className="flex flex-row items-center space-x-12 mb-4">
                  <button
                    onClick={handleSubmit}
                    disabled={loading || !currentState.fingerprint}
                    className="btn btn-primary"
                  >
                    {loading ? 'Generating...' : 'Generate Credential History'}
                  </button>
                </div>
              </div>
            )}
          </div>

          {verificationStatus && (
            <div className="row">
              <div className="col-12">
                <div className={`alert ${verificationStatus.includes('successful') ? 'alert-success' : 'alert-danger'} mb-6 rounded px-4 py-3`}>
                  {verificationStatus}
                </div>
              </div>
            </div>
          )}
        </div>

        {verificationStatus && verificationStatus.includes('successful') && (
          <div className="bg-gray-800 p-4 rounded mb-6">
            <h4 className="text-lg font-semibold mb-2">What you have attested to:</h4>
            <ul className="list-disc pl-4 space-y-2">
              <li>The client's current location is within the specified geohash precision:
                <ul className="list-disc pl-4 mt-1">
                  <li>Using {options.serverGeohashBits} bits of precision</li>
                  <li>Bounding box size: {
                    options.serverGeohashBits === 15 ? "~156km x ~156km" :
                      options.serverGeohashBits === 20 ? "~39km x ~19.5km" :
                        "~5km x ~5km"
                  }</li>
                </ul>
              </li>
              <li>The client's current browser fingerprint is sufficiently similar to their previous state:
                <ul className="list-disc pl-4 mt-1">
                  <li>Required similarity: {
                    options.serverFingerprintThreshold === 350 ? "70%" :
                      options.serverFingerprintThreshold === 400 ? "80%" :
                        "90%"
                  }</li>
                  <li>Generated similarity: {options.fingerprintSimilarity}%</li>
                </ul>
              </li>
              <li>The client's IP address history is consistent with their current location</li>
              <li>All cryptographic signatures are valid</li>
            </ul>

            <div className="mt-4">
              <h5 className="text-md font-semibold mb-2">Performance metrics:</h5>
              <ul className="list-disc pl-4 space-y-2">
                <li>Proving time: {provingTime?.toFixed(2)}ms</li>
                <li>Verifying time: {verifyingTime?.toFixed(2)}ms</li>
              </ul>
            </div>
          </div>
        )}

        {verificationStatus && (
          <div className="mb-6">
            <div
              onClick={() => setIsVerificationInputsExpanded(!isVerificationInputsExpanded)}
              className="cursor-pointer bg-gray-800 rounded px-4 py-3 hover:bg-gray-700 transition-colors select-none"
              role="button"
              tabIndex={0}
              aria-expanded={isVerificationInputsExpanded}
            >
              <div className="flex items-center">
                <h5 className="text-white text-lg font-semibold m-0 p-0 leading-tight">
                  Verification input, output, and signatures
                </h5>
                <svg
                  className={`chevron-icon ml-2 align-middle transition-transform duration-200 ${isVerificationInputsExpanded ? 'rotate-180' : ''} text-white`}
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  style={{ display: 'inline-block', verticalAlign: 'middle' }}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
                </svg>
              </div>
            </div>
            {isVerificationInputsExpanded && (
              <div className="bg-gray-800 rounded-b px-4 pb-4 pt-2">
                <p className="mb-2">The inputs to the verification circuit are shown below. Note that all random numbers are hardcoded to strings of 1s for simplicity.</p>
                <div className="list-group">
                  <div className="list-group-item bg-gray-800 text-white">
                    <strong>State inputs:</strong>
                    <pre className="text-sm font-mono whitespace-pre-wrap mt-2">
                      {JSON.stringify({
                        ips: originalState.ips.map(ipToIntString),
                        geohashes: originalState.geohashes.map(geohashToIntString),
                        last_fingerprint: originalState.fingerprint,
                        users_prf_seed: "1111111111",
                        state_counter: "0",
                        initial_comm_rand: "111111111",
                        state_comm_randomness: "111111111"
                      }, null, 2)}
                    </pre>
                  </div>
                  <div className="list-group-item bg-gray-800 text-white">
                    <strong>New state:</strong>
                    <pre className="text-sm font-mono whitespace-pre-wrap mt-2">
                      {JSON.stringify({
                        ips: ipAddresses.map(ipToIntString),
                        geohashes: geohashes.map(geohashToIntString),
                        last_fingerprint: currentState.fingerprint,
                      }, null, 2)}
                    </pre>
                  </div>
                  <div className="list-group-item bg-gray-800 text-white">
                    <strong>Signatures:</strong>
                    <div className="mt-2">
                      <div className="font-mono text-sm">
                        <div>Initial State R8x: <code>{signatures.initial_state?.r8x || "Not available"}</code></div>
                        <div>Initial State R8y: <code>{signatures.initial_state?.r8y || "Not available"}</code></div>
                        <div>Initial State S: <code>{signatures.initial_state?.s || "Not available"}</code></div>
                      </div>
                      <div className="font-mono text-sm mt-2">
                        <div>New User Info R8x: <code>{signatures.new_user_info?.r8x || "Not available"}</code></div>
                        <div>New User Info R8y: <code>{signatures.new_user_info?.r8y || "Not available"}</code></div>
                        <div>New User Info S: <code>{signatures.new_user_info?.s || "Not available"}</code></div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        <div className="mb-4">
          <h2 className="text-xl font-semibold mb-2">Server-side verification parameters</h2>
          <div className="bg-gray-800 p-4 rounded mb-4">
            <p className="mb-2">These parameters determine how strict the verification process is. In this demo, you can set these parameters yourself as if you were the server. However, calculating these thresholds based on exact statistics may not be privacy preserving. Our work validates a system for using <strong><a href='https://en.wikipedia.org/wiki/Local_differential_privacy' target='_blank' rel='noopener noreferrer' className="orange-link">local differential privacy</a></strong> (specifically <a href='https://github.com/google/rappor' target='_blank' rel='noopener noreferrer' className="orange-link">RAPPOR</a>) to calculate these thresholds.</p>
            <ul className="list-disc pl-4 space-y-2">
              <li><strong>Geohash precision:</strong> Controls how precise the location verification is:
                <ul className="list-disc pl-4 mt-1">
                  <li>3 characters (15 bits): ~156km x ~156km bounding box</li>
                  <li>4 characters (20 bits): ~39km x ~19.5km bounding box</li>
                  <li>5 characters (25 bits): ~5km x ~5km bounding box</li>
                </ul>
              </li>
              <li><strong>Fingerprint similarity:</strong> Controls how similar fingerprints must be to pass verification:
                <ul className="list-disc pl-4 mt-1">
                  <li>Loose: 70% similarity required</li>
                  <li>Medium: 80% similarity required</li>
                  <li>Strict: 90% similarity required</li>
                </ul>
              </li>
            </ul>

            <div className="row mt-4">
              <div className="col-md-6 mb-3">
                <label className="form-label">Geohash precision</label>
                <select
                  className="form-select bg-gray-800 text-white border-2 border-gray-700 hover:border-blue-500 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 rounded-lg p-2 cursor-pointer transition-colors duration-200"
                  value={options.serverGeohashBits}
                  onChange={(e) => setOptions({ ...options, serverGeohashBits: parseInt(e.target.value) })}
                >
                  {geohashConfigs.map(config => (
                    <option key={config.bits} value={config.bits}>
                      {config.label}
                    </option>
                  ))}
                </select>
              </div>
              <div className="col-md-6 mb-3">
                <label className="form-label">Fingerprint similarity</label>
                <select
                  className="form-select bg-gray-800 text-white border-2 border-gray-700 hover:border-blue-500 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 rounded-lg p-2 cursor-pointer transition-colors duration-200"
                  value={options.serverFingerprintThreshold}
                  onChange={(e) => setOptions({ ...options, serverFingerprintThreshold: parseInt(e.target.value) })}
                >
                  {fingerprintConfigs.map(config => (
                    <option key={config.threshold} value={config.threshold}>
                      {config.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </div>
        </div>

        <div className="mb-4">
          <h2 className="text-xl font-semibold mb-2">How this works</h2>
          <div className="bg-gray-800 p-4 rounded mb-4">
            <p className="mb-2">This demo website shows how <a href="https://en.wikipedia.org/wiki/Zero-knowledge_proof" target="_blank" rel="noopener noreferrer" className="orange-link">zero-knowledge proof</a>-based anonymous credentials can verify that a user's state is within normal parameters while maintaining privacy. All data is generated and stored locally in your browser's local storage. We envision this being used for a wide range of applications, for example:</p>
            <ul className="list-disc pl-4 space-y-2">
              <li>Verifying that a user is logging in from a location that they've previously logged-in from</li>
              <li>Verifying that the current device that they're using is similar to a device that they've used in the past</li>
              <li>Attributing ad clicks</li>
              <li>Verifying that a user has recently passed a humanness check</li>
            </ul>
            <p className="mb-2">On this site, we allow you to view and configure the entire system, both client- and server-side. The <strong>client-side parameters</strong> control how the test data is generated (e.g. how similar the generated fingerprint and location history are to the user's current state), and the <strong>server-side parameters</strong> control how strict the verification process is (e.g. how similar the fingerprint and location history must be to the user's current state to pass verification).</p>
            <p className="mb-2">If a verification check is passed, it's equivalent to the client saying to the server (without revealing any sensitive information about their current state) that:</p>
            <ol className="list-decimal pl-4 space-y-2">
              <li>The IP and geohash lists are not empty</li>
              <li>The new geohash shares enough prefix bits with at least one of the old geohashes (based on the selected precision)</li>
              <li>The current fingerprint is sufficiently similar to the initial fingerprint (based on the selected threshold)</li>
            </ol>
          </div>
        </div>
      </div>

      {/*
      <footer className="bg-gray-800 border-t border-gray-700 py-6 mt-8">
        <div className="container">
          <div className="text-center text-gray-400 text-sm">
            <p className="mb-2">
              A work in progress being developed by{' '}
              <a href="https://haltriedman.com" target="_blank" rel="noopener noreferrer" className="orange-link">Hal Triedman</a>
              {', '}
              <a href="https://www.sasha.place/" target="_blank" rel="noopener noreferrer" className="orange-link">Sasha Frolov</a>
              {', and '}
              <a href="https://www.cs.umd.edu/~imiers/" target="_blank" rel="noopener noreferrer" className="orange-link">Ian Miers</a>
            </p>
            <p className="mb-2">
              <a href="https://github.com/htried/zkp-ldp" target="_blank" rel="noopener noreferrer" className="orange-link">
                Source code on GitHub
              </a>
            </p>
            <p>
              Licensed under{' '}
              <a href="https://github.com/htried/zkp-ldp/blob/main/LICENSE" target="_blank" rel="noopener noreferrer" className="orange-link">
                Apache License 2.0
              </a>
            </p>
          </div>
        </div>
      </footer>
      */}
    </div>
  );
}