import {
  AnonAadhaarProof,
  LogInWithAnonAadhaar,
  useAnonAadhaar,
  useProver,
} from "@anon-aadhaar/react";
import { useEffect, useState } from "react";
import axios from "axios";
import key from "./vkey.json";

type HomeProps = {
  setUseTestAadhaar: (state: boolean) => void;
  useTestAadhaar: boolean;
};

export default function Home({ setUseTestAadhaar, useTestAadhaar }: HomeProps) {
  // Use the Country Identity hook to get the status of the user.
  const [anonAadhaar] = useAnonAadhaar();
  const [, latestProof] = useProver();
  const[tx, setTx] = useState<string>("");
  const API_URL = 'https://relayer-api.horizenlabs.io/api/v1';

  useEffect(() => {
    if (anonAadhaar.status === "logged-in") {
      console.log(anonAadhaar.status);
    }
  }, [anonAadhaar]);

  const switchAadhaar = () => {
    setUseTestAadhaar(!useTestAadhaar);
  };

  const verifyProofWithRelayer = async () => {
    const params = {
        "proofType": "groth16",
        "vkRegistered": false,
        "proofOptions": {
            "library": "snarkjs",
            "curve": "bn128"
        },
        "proofData": {
            "proof": latestProof?.proof.groth16Proof,
            "publicSignals": [latestProof?.proof.pubkeyHash, latestProof?.proof.nullifier, latestProof?.proof.timestamp, latestProof?.proof.ageAbove18, latestProof?.proof.gender, latestProof?.proof.pincode, latestProof?.proof.state, latestProof?.proof.nullifierSeed, latestProof?.proof.signalHash],
            "vk": key
        }    
    }
    const requestResponse = await axios.post(`${API_URL}/submit-proof/${process.env.NEXT_PUBLIC_API_KEY}`, params);

    while(true){
        const jobStatusResponse = await axios.get(`${API_URL}/job-status/${process.env.NEXT_PUBLIC_API_KEY}/${requestResponse.data.jobId}`);
        if(jobStatusResponse.data.status === "IncludedInBlock"){
            console.log("Job finalized successfully");
            console.log(jobStatusResponse.data);
            setTx(`https://zkverify-testnet.subscan.io/extrinsic/${jobStatusResponse.data.txHash}`)
            break;
        }else{
            console.log("Job status: ", jobStatusResponse.data.status);
            console.log("Waiting for job to finalize...");
            await new Promise(resolve => setTimeout(resolve, 5000)); // Wait for 5 seconds before checking again
        }
    }

    
  }

  return (
    <div className="min-h-screen bg-gray-100 px-4 py-8">
      <main className="flex flex-col items-center gap-8 bg-white rounded-2xl max-w-screen-sm mx-auto h-[24rem] md:h-[20rem] p-8">
        <h1 className="font-bold text-2xl">Welcome to Anon Aadhaar Example</h1>
        <p>Prove your Identity anonymously using your Aadhaar card.</p>

        {/* Import the Connect Button component */}
        <LogInWithAnonAadhaar nullifierSeed={1234} />

        {useTestAadhaar ? (
          <p>
            You&apos;re using the <strong> test </strong> Aadhaar mode
          </p>
        ) : (
          <p>
            You&apos;re using the <strong> real </strong> Aadhaar mode
          </p>
        )}
        <button
          onClick={switchAadhaar}
          type="button"
          className="rounded bg-white px-2 py-1 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Switch for {useTestAadhaar ? "real" : "test"}
        </button>
      </main>
      <div className="flex flex-col items-center gap-4 rounded-2xl max-w-screen-sm mx-auto p-8">
        {/* Render the proof if generated and valid */}
        {anonAadhaar.status === "logged-in" && (
          <>
            <p>✅ Proof is valid</p>
            <p>Got your Aadhaar Identity Proof</p>
            <>Welcome anon!</>
            {latestProof && (
              <AnonAadhaarProof code={JSON.stringify(latestProof, null, 2)} />
            )}
            <button onClick={verifyProofWithRelayer} className="rounded bg-white px-2 py-1 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"            >
              Verify Proof
            </button>
            {tx!="" && (<h2><a href={tx}>Click here to check your transaction</a></h2>)}
          </>
        )}
      </div>
    </div>
  );
}
