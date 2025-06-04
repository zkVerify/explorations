// Import necessary libraries
import { zkVerifySession, Library, CurveType, ZkVerifyEvents } from "zkverifyjs";
import zkeSDK from "@zk-email/sdk";
import fs from "fs/promises";
import dotenv from 'dotenv';
dotenv.config();

async function main() {

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

    // Start a zkVerify session
    const session = await zkVerifySession.start().Volta().withAccount(process.env.SEED_PHRASE);

    // Verify the proof using the zkVerify session
    const {events} = await session.verify()
        .groth16({library: Library.snarkjs, curve: CurveType.bn128})
        .execute({proofData: {
            vk: JSON.parse(vkey),
            proof: proof.props.proofData,
            publicSignals: proof.props.publicOutputs
        }});

    // Listen for events
    events.on(ZkVerifyEvents.IncludedInBlock, (eventData) => {
        console.log("Included in block", eventData);
        session.close().then(r => process.exit(0));
    })

}

main()