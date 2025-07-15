use std::{env, fs, thread, time::Duration};
use anyhow::{Ok, Result};
use dotenv::dotenv;
use reqwest::Client;
use risc0_zkvm::Receipt;
use serde::Deserialize;

const API_URL: &str = "https://relayer-api.horizenlabs.io/api/v1";


pub async fn verify_proof(receipt: Receipt, image_id: String) -> Result<()>{

    dotenv().ok();
    let api_key = env::var("API_KEY")?;

    let mut bin_receipt = Vec::new();
    ciborium::into_writer(&receipt, &mut bin_receipt).unwrap();
    let proof_hex = hex::encode(&bin_receipt);
    let public_inputs_hex = hex::encode(&receipt.journal.bytes);

    let client = Client::new();

    let submit_params = serde_json::json!({
        "proofType": "risc0",
        "vkRegistered": false,
        "chainId": 11155111,
        "proofOptions": {
            "version": "V2_1"
        },
        "proofData": {
            "proof": "0x".to_string() + &proof_hex,
            "publicSignals": "0x".to_string() + &public_inputs_hex,
            "vk": image_id
        }
    });

    let response = client
        .post(format!("{}/submit-proof/{}", API_URL, api_key))
        .json(&submit_params)
        .send()
        .await?;

    let submit_response: serde_json::Value = response.json().await?;
    println!("{:#?}", submit_response);

    if submit_response["optimisticVerify"] != "success" {
        eprintln!("Proof verification failed.");
        return Ok(());
    }

    let job_id = submit_response["jobId"].as_str().unwrap();

    loop {
        let job_status = client
            .get(format!("{}/job-status/{}/{}", API_URL, api_key, job_id))
            .send()
            .await?
            .json::<serde_json::Value>()
            .await?;

        let status = job_status["status"].as_str().unwrap_or("Unknown");

        if status == "Finalized" || status == "Aggregated" || status == "AggregationPending"{
            println!("Job Finalized successfully");
            println!("{:?}", job_status);
            break;
        } else {
            println!("Job status: {}", status);
            println!("Waiting for job to finalized...");
            thread::sleep(Duration::from_secs(5));
        }
    }

    Ok(())
}