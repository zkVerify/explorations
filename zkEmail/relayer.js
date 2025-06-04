import axios from 'axios';
import zkeSDK, { Proof } from "@zk-email/sdk";
import fs from "fs/promises";
import dotenv from 'dotenv';
dotenv.config();

async function main() {

    const API_URL = 'https://relayer-api.horizenlabs.io/api/v1';

    // Initialize the SDK
    const sdk = zkeSDK();
    
    // Get blueprint from the registry
    const blueprint = await sdk.getBlueprint("Bisht13/SuccinctZKResidencyInvite@v3");

    // Download the vkey
    const vkey = await blueprint.getVkey();
    const prover = blueprint.createProver();

    // Read email file
    const eml = await fs.readFile("residency.EML", "utf-8");
    
    // Generate the proof
    const proof = await prover.generateProof(eml);

    // API call parameters
    const params = {
        "proofType": "groth16",
        "vkRegistered": false,
        "proofOptions": {
            "library": "snarkjs",
            "curve": "bn128"
        },
        "proofData": {
            "proof": proof.props.proofData,
            "publicSignals": proof.props.publicOutputs,
            "vk": JSON.parse(vkey)
        }    
    }

    // POST API CALL to submit the proof
    const requestResponse = await axios.post(`${API_URL}/submit-proof/${process.env.RELAYER_API_KEY}`, params)
    console.log(requestResponse.data)

    // Check if the optimistic verification was successful
    if(requestResponse.data.optimisticVerify != "success"){
        console.error("Proof verification, check proof artifacts");
        return;
    }

    // Polling for job status 
    while(true){
        const jobStatusResponse = await axios.get(`${API_URL}/job-status/${process.env.RELAYER_API_KEY}/${requestResponse.data.jobId}`);
        if(jobStatusResponse.data.status === "Finalized"){
            console.log("Job finalized successfully");
            console.log(jobStatusResponse.data);
            process.exit(0);
        }else{
            console.log("Job status: ", jobStatusResponse.data.status);
            console.log("Waiting for job to finalize...");
            await new Promise(resolve => setTimeout(resolve, 5000)); // Wait for 5 seconds before checking again
        }
    }
}

main();