package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/vocdoni/circom2gnark/parser"
)

func main() {
	start := time.Now() // Start total timer

	// Read files
	proofData, err := os.ReadFile("../zk_cred_logic/proofs/add_new_ip_not_full.json")
	if err != nil {
		log.Fatalf("failed to read proof: %v", err)
	}

	vkData, err := os.ReadFile("../zk_cred_logic/verification_key.json")
	if err != nil {
		log.Fatalf("failed to read verification key: %v", err)
	}

	publicSignalsData, err := os.ReadFile("../zk_cred_logic/publics/add_new_ip_not_full.json")
	if err != nil {
		log.Fatalf("failed to read public signals: %v", err)
	}

	// Unmarshal data
	snarkProof, err := parser.UnmarshalCircomProofJSON(proofData)
	if err != nil {
		log.Fatalf("failed to unmarshal proof: %v", err)
	}

	snarkVk, err := parser.UnmarshalCircomVerificationKeyJSON(vkData)
	if err != nil {
		log.Fatalf("failed to unmarshal verification key: %v", err)
	}

	publicSignals, err := parser.UnmarshalCircomPublicSignalsJSON(publicSignalsData)
	if err != nil {
		log.Fatalf("failed to unmarshal public signals: %v", err)
	}

	// Convert Circom proof to Gnark proof
	gnarkProof, err := parser.ConvertCircomToGnark(snarkProof, snarkVk, publicSignals)
	if err != nil {
		log.Fatalf("failed to convert Circom proof to Gnark proof: %v", err)
	}

	// Time the proof verification specifically
	verifyStart := time.Now()
	verified, err := parser.VerifyProof(gnarkProof)
	verifyDuration := time.Since(verifyStart)

	if err != nil {
		log.Fatalf("failed to verify proof: %v", err)
	}
	if !verified {
		log.Fatalf("proof verification failed")
	}
	fmt.Println("Proof verification succeeded!")

	totalDuration := time.Since(start)

	fmt.Printf("Time taken for VerifyProof: %v\n", verifyDuration)
	fmt.Printf("Total execution time: %v\n", totalDuration)
}
