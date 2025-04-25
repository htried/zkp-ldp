pragma circom 2.2.0;

include "../circomlib/circuits/bitify.circom";
include "../circomlib/circuits/comparators.circom";
include "../circomlib/circuits/gates.circom";

// Computes the similarity score between 2 hashes, consisting
// of num_blocks field elements. I have decided that each field element
// will pack 250 bits of hash. Outputs the similarity score between them,
// which is the number of bits that agree in the 2 hashes. This is different
// Avoids doing fractions in circuit.
template HashSimilarityScore(num_blocks) {
    var hash_bits_per_block = 250;

    signal input hash1[num_blocks];
    signal input hash2[num_blocks];

    signal output similarity_score;

    component hash1_to_bits[num_blocks];
    component hash2_to_bits[num_blocks];
    for(var i = 0; i < num_blocks; i++) {
        hash1_to_bits[i] = Num2Bits(hash_bits_per_block);
        hash1_to_bits[i].in <== hash1[i];

        hash2_to_bits[i] = Num2Bits(hash_bits_per_block);
        hash2_to_bits[i].in <== hash2[i];
    }

    component equals_for_similarity_score[num_blocks * hash_bits_per_block];
    signal running_sum[num_blocks * hash_bits_per_block];
    for (var i = 0; i < num_blocks; i++) {
        for (var j = 0; j < hash_bits_per_block; j++) {
            var flattened_index = i * hash_bits_per_block + j;
            equals_for_similarity_score[flattened_index] = IsEqual();
            equals_for_similarity_score[flattened_index].in[0] <== hash1_to_bits[i].out[j];
            equals_for_similarity_score[flattened_index].in[1] <== hash2_to_bits[i].out[j];

            if (flattened_index != 0) {
                running_sum[flattened_index] <== equals_for_similarity_score[flattened_index].out + running_sum[flattened_index - 1];
            } else {
                running_sum[flattened_index] <== equals_for_similarity_score[flattened_index].out;
            }
        }
    }
    similarity_score <== running_sum[num_blocks * hash_bits_per_block - 1];
}