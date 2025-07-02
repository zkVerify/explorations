pragma circom 2.1.5;

include "node_modules/circomlib/circuits/comparators.circom";

template GeolocationProver() {
    // === Private Inputs ===
    // These are the secret GPS coordinates, converted to integers by scaling.
    signal input lat1;
    signal input lon1;
    signal input lat2;
    signal input lon2;

    // === Public Inputs ===
    // This is the distance threshold the proof is checked against. It is public knowledge.
    signal input threshold;

    // === Intermediate Calculations ===

    // 1. Calculate the difference in latitude and longitude.
    // The result can be positive or negative, which is fine.
    signal delta_lat;
    delta_lat <== lat1 - lat2;

    signal delta_lon;
    delta_lon <== lon1 - lon2;

    // 2. Square the differences.
    // This gives us the squared difference along each axis.
    signal delta_lat_sq;
    delta_lat_sq <== delta_lat * delta_lat;

    signal delta_lon_sq;
    delta_lon_sq <== delta_lon * delta_lon;

    // 3. Sum the squares to get the final squared Euclidean distance.
    signal dist_sq;
    dist_sq <== delta_lat_sq + delta_lon_sq;

    // === Constraint ===
    // The core of the proof. We check if the calculated squared distance
    // is less than the public squared threshold.
    // The LessThan comparator takes the number of bits for the inputs.
    // 252 is a safe, standard value that is large enough to hold our numbers
    // and fits within the field size of common curves like bn128.
    component is_within_range = LessThan(252);
    is_within_range.in[0] <== dist_sq;
    is_within_range.in[1] <== threshold;

    // 4. Constrain the output of the comparator to be 1 (true).
    // This forces the circuit to only be satisfiable if dist_sq < threshold_sq.
    // If the distance is not within the threshold, proof generation will fail.
    is_within_range.out === 1;
}

// Instantiate the main component.
component main {public [lat2, lon2, threshold]} = GeolocationProver();

/* INPUT = {
    "lat1": "13198600",
    "lon1": "77706600",
    "lat2": "12845200",
    "lon2": "77660200",
    "threshold": "202905202500"
} */