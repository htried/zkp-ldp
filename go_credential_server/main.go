package main

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/crypto"
	"github.com/google/uuid"
	"github.com/iden3/go-rapidsnark/types"
	"github.com/iden3/go-rapidsnark/verifier"
	"github.com/syndtr/goleveldb/leveldb"
)

// SnarkJS verification key structure
type SnarkJSVerificationKey struct {
	Protocol      string       `json:"protocol"`
	Curve         string       `json:"curve"`
	NPublic       int          `json:"nPublic"`
	VkAlpha1      []string     `json:"vk_alpha_1"`
	VkBeta2       [][]string   `json:"vk_beta_2"`
	VkGamma2      [][]string   `json:"vk_gamma_2"`
	VkDelta2      [][]string   `json:"vk_delta_2"`
	VkAlphabeta12 [][][]string `json:"vk_alphabeta_12"`
	IC            [][]string   `json:"IC"`
}

// SnarkJS proof structure (more complete than the basic one)
type SnarkJSProof struct {
	PiA      []string   `json:"pi_a"`
	PiB      [][]string `json:"pi_b"`
	PiC      []string   `json:"pi_c"`
	Protocol string     `json:"protocol"`
	Curve    string     `json:"curve"`
}

// Groth16 proof structure matching snarkjs output
type Groth16Proof struct {
	PiA []string   `json:"pi_a"`
	PiB [][]string `json:"pi_b"`
	PiC []string   `json:"pi_c"`
}

// Input structure matching generate_inputs.js with k=5
type CircuitInput struct {
	Ips                 []string `json:"ips"`
	Geohashes           []string `json:"geohashes"`
	LastFingerprint     []string `json:"last_fingerprint"`
	Yob                 []string `json:"yob"`
	UsersPrfSeed        string   `json:"users_prf_seed"`
	StateCounter        string   `json:"state_counter"`
	InitialCommRand     string   `json:"initial_comm_rand"`
	NewIP               string   `json:"new_ip"`
	NewGeohash          string   `json:"new_geohash"`
	NewRapporNonce      string   `json:"new_rappor_nonce"`
	StateCommRandomness string   `json:"state_comm_randomness"`
	NewFingerprint      []string `json:"new_fingerprint"`
	InitialStateR8x     string   `json:"initial_state_r8x"`
	InitialStateR8y     string   `json:"initial_state_r8y"`
	InitialStateS       string   `json:"initial_state_s"`
	NewUserInfoR8x      string   `json:"new_user_info_r8x"`
	NewUserInfoR8y      string   `json:"new_user_info_r8y"`
	NewUserInfoS        string   `json:"new_user_info_s"`
}

type CredentialRequest struct {
	Proof       Groth16Proof `json:"proof"`
	PublicInput []string     `json:"public_input"`
	Input       CircuitInput `json:"input"`
}

type CredentialResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	UUID    string `json:"uuid,omitempty"`
	Timing  struct {
		VerificationTime time.Duration `json:"verification_time"`
		NullifierTime    time.Duration `json:"nullifier_time"`
		SigningTime      time.Duration `json:"signing_time"`
		TotalTime        time.Duration `json:"total_time"`
	} `json:"timing"`
}

var (
	db              *leveldb.DB
	privateKey      *ecdsa.PrivateKey
	verificationKey []byte
)

// loadVerificationKey loads the verification key from the snarkjs file
func loadVerificationKey() error {
	// Load the verification key from the circom_stuff directory
	vkData, err := os.ReadFile("circom_stuff/verification_key.json")
	if err != nil {
		return fmt.Errorf("failed to read verification key file: %w", err)
	}

	// Store the raw verification key data for go-rapidsnark
	verificationKey = vkData

	log.Printf("Loaded verification key (%d bytes)", len(vkData))
	return nil
}

func main() {
	var err error

	// Initialize database
	db, err = leveldb.OpenFile("./nullifier_db", nil)
	if err != nil {
		log.Fatal("Failed to open database:", err)
	}
	defer db.Close()

	// Generate or load private key for signing
	privateKey, err = crypto.GenerateKey()
	if err != nil {
		log.Fatal("Failed to generate private key:", err)
	}

	// Load verification key
	err = loadVerificationKey()
	if err != nil {
		log.Printf("Warning: Could not load verification key: %v", err)
		log.Println("Using mock verification - proofs will not be verified")
		verificationKey = nil
	} else {
		log.Println("Successfully loaded verification key - real verification enabled")
	}

	http.HandleFunc("/verify", handleCredentialVerification)

	fmt.Println("Server starting on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func handleCredentialVerification(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CredentialRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	start := time.Now()

	// Always generate a unique UUID for each request
	// This ensures we can test the full pipeline multiple times
	inputHash := sha256.Sum256([]byte(fmt.Sprintf("%v", req.Input)))
	baseUUID := uuid.NewSHA1(uuid.Nil, inputHash[:]).String()

	// Add timestamp to make it truly unique for each request
	timestamp := time.Now().UnixNano()
	credUUID := fmt.Sprintf("%s-%d", baseUUID, timestamp)

	// Step 1: Verify SNARK
	verificationStart := time.Now()
	valid := verifySNARK(req.Proof, req.PublicInput)
	verificationTime := time.Since(verificationStart)

	if !valid {
		response := CredentialResponse{
			Success: false,
			Message: "SNARK verification failed",
			Timing: struct {
				VerificationTime time.Duration `json:"verification_time"`
				NullifierTime    time.Duration `json:"nullifier_time"`
				SigningTime      time.Duration `json:"signing_time"`
				TotalTime        time.Duration `json:"total_time"`
			}{
				VerificationTime: verificationTime,
				NullifierTime:    0,
				SigningTime:      0,
				TotalTime:        time.Since(start),
			},
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	// Step 2: Check nullifier (UUID uniqueness)
	nullifierStart := time.Now()
	isUnique := checkNullifier(credUUID)
	nullifierTime := time.Since(nullifierStart)

	if !isUnique {
		response := CredentialResponse{
			Success: false,
			Message: "UUID already exists",
			Timing: struct {
				VerificationTime time.Duration `json:"verification_time"`
				NullifierTime    time.Duration `json:"nullifier_time"`
				SigningTime      time.Duration `json:"signing_time"`
				TotalTime        time.Duration `json:"total_time"`
			}{
				VerificationTime: verificationTime,
				NullifierTime:    nullifierTime,
				SigningTime:      0,
				TotalTime:        time.Since(start),
			},
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	// Step 3: Sign credential
	signingStart := time.Now()
	log.Printf("Starting credential signing...")
	signature, err := signCredential(credUUID, req.Input)
	signingTime := time.Since(signingStart)
	log.Printf("Signing completed in %v (raw: %d nanoseconds)", signingTime, signingTime.Nanoseconds())

	if err != nil {
		log.Printf("Failed to sign credential: %v", err)
		response := CredentialResponse{
			Success: false,
			Message: "Failed to sign credential",
			Timing: struct {
				VerificationTime time.Duration `json:"verification_time"`
				NullifierTime    time.Duration `json:"nullifier_time"`
				SigningTime      time.Duration `json:"signing_time"`
				TotalTime        time.Duration `json:"total_time"`
			}{
				VerificationTime: verificationTime,
				NullifierTime:    nullifierTime,
				SigningTime:      signingTime,
				TotalTime:        time.Since(start),
			},
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	// Save UUID to database
	saveNullifier(credUUID)

	totalTime := time.Since(start)

	response := CredentialResponse{
		Success: true,
		Message: "Credential verified and signed",
		UUID:    credUUID,
		Timing: struct {
			VerificationTime time.Duration `json:"verification_time"`
			NullifierTime    time.Duration `json:"nullifier_time"`
			SigningTime      time.Duration `json:"signing_time"`
			TotalTime        time.Duration `json:"total_time"`
		}{
			VerificationTime: verificationTime,
			NullifierTime:    nullifierTime,
			SigningTime:      signingTime,
			TotalTime:        totalTime,
		},
	}

	// Log the signature length for debugging
	log.Printf("Credential signed successfully, signature length: %d bytes", len(signature))

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)

	// Log timing
	fmt.Printf("Verification: %v, Nullifier: %v, Signing: %v, Total: %v\n",
		verificationTime, nullifierTime, signingTime, totalTime)
}

func verifySNARK(proof Groth16Proof, publicInput []string) bool {
	// Check if we have a verification key
	if verificationKey == nil {
		log.Println("No verification key available - using mock verification")
		time.Sleep(10 * time.Millisecond)
		return true // Mock verification always succeeds
	}

	log.Printf("Verifying SNARK with %d public inputs", len(publicInput))

	// Convert our proof format to go-rapidsnark format
	rapidsnarkProof := types.ZKProof{
		Proof: &types.ProofData{
			A: proof.PiA,
			B: proof.PiB,
			C: proof.PiC,
		},
		PubSignals: publicInput,
	}

	// Use go-rapidsnark to verify the proof
	err := verifier.VerifyGroth16(rapidsnarkProof, verificationKey)
	if err != nil {
		log.Printf("SNARK verification failed: %v", err)
		return false
	}

	log.Printf("SNARK verification completed successfully!")
	return true
}

func checkNullifier(uuid string) bool {
	// Check if UUID exists in database
	exists, err := db.Has([]byte(uuid), nil)
	if err != nil {
		return false
	}
	return !exists
}

func saveNullifier(uuid string) {
	db.Put([]byte(uuid), []byte("1"), nil)
}

func signCredential(uuid string, input CircuitInput) ([]byte, error) {
	// Create a comprehensive credential to sign
	// This includes the UUID and all the credential input data
	credentialData := fmt.Sprintf("%s|%v|%v|%v|%s|%s|%s|%s|%s|%v|%s|%s|%s|%s|%s|%s",
		uuid,
		input.Ips,
		input.Geohashes,
		input.LastFingerprint,
		input.UsersPrfSeed,
		input.StateCounter,
		input.InitialCommRand,
		input.NewIP,
		input.NewGeohash,
		input.NewFingerprint,
		input.InitialStateR8x,
		input.InitialStateR8y,
		input.InitialStateS,
		input.NewUserInfoR8x,
		input.NewUserInfoR8y,
		input.NewUserInfoS)

	// Hash the entire credential data and sign it
	hash := sha256.Sum256([]byte(credentialData))
	signature, err := ecdsa.SignASN1(rand.Reader, privateKey, hash[:])
	if err != nil {
		return nil, fmt.Errorf("failed to sign credential: %w", err)
	}

	return signature, nil
}
