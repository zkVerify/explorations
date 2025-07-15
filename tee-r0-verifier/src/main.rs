mod utils;

use std::{fs::read_to_string, path::PathBuf};
use anyhow::Result;
use dcap_bonsai_cli::chain::{
    pccs::{
        enclave_id::{get_enclave_identity, EnclaveIdType},
        fmspc_tcb::get_tcb_info,
        pcs::{get_certificate_by_id, IPCSDao::CA},
    },
};
use dcap_bonsai_cli::code::DCAP_GUEST_ELF;
use dcap_bonsai_cli::collaterals::Collaterals;
use dcap_bonsai_cli::constants::*;
use dcap_bonsai_cli::parser::get_pck_fmspc_and_issuer;
use dcap_bonsai_cli::remove_prefix_if_found;
use dotenv::dotenv;
use risc0_zkvm::{compute_image_id, default_prover, ExecutorEnv, ProverOpts};

#[tokio::main]
async fn main() -> Result<()>{
    dotenv().ok();

    let quote = get_quote().expect("Failed to read quote");

    // Step 1: Determine quote version and TEE type
    let quote_version = u16::from_le_bytes([quote[0], quote[1]]);
    let tee_type = u32::from_le_bytes([quote[4], quote[5], quote[6], quote[7]]);

    println!("Quote version: {}", quote_version);
    println!("TEE Type: {}", tee_type);

    if quote_version < 3 || quote_version > 4 {
        panic!("Unsupported quote version");
    }

    if tee_type != SGX_TEE_TYPE && tee_type != TDX_TEE_TYPE {
        panic!("Unsupported tee type");
    }

    // Step 2: Load collaterals
    println!("Quote read successfully. Begin fetching collaterals from the on-chain PCCS");

    let (root_ca, root_ca_crl) = get_certificate_by_id(CA::ROOT).await?;
    if root_ca.is_empty() || root_ca_crl.is_empty() {
        panic!("Intel SGX Root CA is missing");
    } else {
        println!("Fetched Intel SGX RootCA and CRL");
    }

    let (fmspc, pck_type, pck_issuer) =
        get_pck_fmspc_and_issuer(&quote, quote_version, tee_type);

    let tcb_type: u8;
    if tee_type == TDX_TEE_TYPE {
        tcb_type = 1;
    } else {
        tcb_type = 0;
    }
    let tcb_version: u32;
    if quote_version < 4 {
        tcb_version = 2
    } else {
        tcb_version = 3
    }
    let tcb_info = get_tcb_info(tcb_type, fmspc.as_str(), tcb_version).await?;

    println!("Fetched TCBInfo JSON for FMSPC: {}", fmspc);

    let qe_id_type: EnclaveIdType;
    if tee_type == TDX_TEE_TYPE {
        qe_id_type = EnclaveIdType::TDQE
    } else {
        qe_id_type = EnclaveIdType::QE
    }
    let qe_identity = get_enclave_identity(qe_id_type, quote_version as u32).await?;
    println!("Fetched QEIdentity JSON");

    let (signing_ca, _) = get_certificate_by_id(CA::SIGNING).await?;
    if signing_ca.is_empty() {
        panic!("Intel TCB Signing CA is missing");
    } else {
        println!("Fetched Intel TCB Signing CA");
    }

    let (_, pck_crl) = get_certificate_by_id(pck_type).await?;
    if pck_crl.is_empty() {
        panic!("CRL for {} is missing", pck_issuer);
    } else {
        println!("Fetched Intel PCK CRL for {}", pck_issuer);
    }

    let collaterals = Collaterals::new(
        tcb_info,
        qe_identity,
        root_ca,
        signing_ca,
        root_ca_crl,
        pck_crl,
    );
    let serialized_collaterals = serialize_collaterals(&collaterals, pck_type);

    // Step 3: Generate the input to upload to Bonsai
    let image_id = compute_image_id(DCAP_GUEST_ELF)?;
    println!("Image ID: {}", image_id.to_string());

    let input = generate_input(&quote, &serialized_collaterals);
    println!("All collaterals found! Begin uploading input to Bonsai...");
    let explicit = std::env::var("RISC0_PROVER").unwrap_or_default();
    println!("{:?}", explicit);
    // Sending proof request to Bonsai
    let env = ExecutorEnv::builder().write_slice(&input).build()?;
    let receipt = default_prover()
        .prove_with_opts(env, DCAP_GUEST_ELF, &ProverOpts::succinct())?
        .receipt;
    receipt.verify(image_id)?;

    utils::verify_proof(receipt, "0x".to_string()+&image_id.to_string()).await?;

    Ok(())
}

fn get_quote() -> Result<Vec<u8>> {

    let mut default_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    default_path.push("data/quote.hex");
    let quote_string = read_to_string(default_path).expect("Wrong data !!!");
    let processed = remove_prefix_if_found(&quote_string);
    let quote_hex = hex::decode(processed)?;
    Ok(quote_hex)

}


fn serialize_collaterals(collaterals: &Collaterals, pck_type: CA) -> Vec<u8> {
    // get the total length
    let total_length = 4 * 8
        + collaterals.tcb_info.len()
        + collaterals.qe_identity.len()
        + collaterals.root_ca.len()
        + collaterals.tcb_signing_ca.len()
        + collaterals.root_ca_crl.len()
        + collaterals.pck_crl.len();

    // create the vec and copy the data
    let mut data = Vec::with_capacity(total_length);
    data.extend_from_slice(&(collaterals.tcb_info.len() as u32).to_le_bytes());
    data.extend_from_slice(&(collaterals.qe_identity.len() as u32).to_le_bytes());
    data.extend_from_slice(&(collaterals.root_ca.len() as u32).to_le_bytes());
    data.extend_from_slice(&(collaterals.tcb_signing_ca.len() as u32).to_le_bytes());
    data.extend_from_slice(&(0 as u32).to_le_bytes()); // pck_certchain_len == 0
    data.extend_from_slice(&(collaterals.root_ca_crl.len() as u32).to_le_bytes());

    match pck_type {
        CA::PLATFORM => {
            data.extend_from_slice(&(0 as u32).to_le_bytes());
            data.extend_from_slice(&(collaterals.pck_crl.len() as u32).to_le_bytes());
        }
        CA::PROCESSOR => {
            data.extend_from_slice(&(collaterals.pck_crl.len() as u32).to_le_bytes());
            data.extend_from_slice(&(0 as u32).to_le_bytes());
        }
        _ => unreachable!(),
    }

    // collateral should only hold one PCK CRL

    data.extend_from_slice(&collaterals.tcb_info);
    data.extend_from_slice(&collaterals.qe_identity);
    data.extend_from_slice(&collaterals.root_ca);
    data.extend_from_slice(&collaterals.tcb_signing_ca);
    data.extend_from_slice(&collaterals.root_ca_crl);
    data.extend_from_slice(&collaterals.pck_crl);

    data
}

fn generate_input(quote: &[u8], collaterals: &[u8]) -> Vec<u8> {
    // get current time in seconds since epoch
    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let current_time_bytes = current_time.to_le_bytes();

    let quote_len = quote.len() as u32;
    let intel_collaterals_bytes_len = collaterals.len() as u32;
    let total_len = 8 + 4 + 4 + quote_len + intel_collaterals_bytes_len;

    let mut input = Vec::with_capacity(total_len as usize);
    input.extend_from_slice(&current_time_bytes);
    input.extend_from_slice(&quote_len.to_le_bytes());
    input.extend_from_slice(&intel_collaterals_bytes_len.to_le_bytes());
    input.extend_from_slice(&quote);
    input.extend_from_slice(&collaterals);

    input.to_owned()
}
