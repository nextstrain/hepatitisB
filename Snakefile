# LINEAGES = ['all']
LINEAGES = ['A2']

# rule all:
#     input:
#         auspice_json = expand("auspice/hepatitisB_{lineage}.json", lineage=LINEAGES)

rule files:
    params:
        reference = "config/reference_hepatitisB_{lineage}.gb",
        auspice_config = "config/auspice_config_{lineage}.json",
        dropped_strains = "config/dropped_strains_hepatitisB_{lineage}.txt"


files = rules.files.params


rule parse:
    message: "Parsing fasta into sequences and metadata"
    input:
        sequences = 'ingest/hepatitisB_{lineage}.fasta'
    output:
        sequences = "results/sequences_hepatitisB_{lineage}.fasta",
        metadata = "results/metadata_hepatitisB_{lineage}.tsv"
    params:
        #strain will be accession number
        fasta_fields = "strain strain_name date country host genotype subgenotype",
    shell:
        """
        augur parse \
            --sequences {input.sequences} \
            --output-sequences {output.sequences} \
            --output-metadata {output.metadata} \
            --fields {params.fasta_fields} \
        """

rule filter:
    message:
        """
        Filtering to
          - {params.sequences_per_group} sequence(s) per {params.group_by!s}
          - minimum genome length of {params.min_length}
        """
    input:
        sequences = rules.parse.output.sequences,
        metadata = rules.parse.output.metadata,
        exclude = files.dropped_strains
    output:
        sequences = "results/filtered_hepatitisB_{lineage}.fasta"
    params:
        group_by = "country year",
        sequences_per_group = 50,
        min_length = 3000
    shell:
        """
        augur filter \
            --sequences {input.sequences} \
            --metadata {input.metadata} \
            --exclude {input.exclude} \
            --output {output.sequences} \
            --group-by {params.group_by} \
            --sequences-per-group {params.sequences_per_group} \
            --min-length {params.min_length}
        """

rule align:
    message:
        """
        Aligning sequences to {input.reference}
          - filling gaps with N
        """
    input:
        sequences = rules.filter.output.sequences,
        reference = files.reference
    threads: 8
    output:
        alignment = "results/aligned_hepatitisB_{lineage}.fasta"
    shell:
        """
        augur align \
            --sequences {input.sequences} \
            --reference-sequence {input.reference} \
            --output {output.alignment} \
            --remove-reference \
            --nthreads {threads} \
            --fill-gaps
        """

rule tree:
    message: "Building tree"
    input:
        alignment = rules.align.output.alignment
    output:
        tree = "results/tree_raw_hepatitisB_{lineage}.nwk"
    threads: 8
    shell:
        """
        augur tree \
            --alignment {input.alignment} \
            --nthreads {threads} \
            --output {output.tree}
        """

rule refine:
    message:
        """
        Refining tree
        NO TIMETREE CURRENTLY
        """
    input:
        tree = rules.tree.output.tree,
        alignment = rules.align.output,
        metadata = rules.parse.output.metadata
    output:
        tree = "results/tree_hepatitisB_{lineage}.nwk",
        node_data = "results/branch_lengths_hepatitisB_{lineage}.json"
    params:
        coalescent = "opt",
        date_inference = "marginal",
        clock_filter_iqd= 4
    shell:
        """
        augur refine \
            --tree {input.tree} \
            --alignment {input.alignment} \
            --metadata {input.metadata} \
            --output-tree {output.tree} \
            --output-node-data {output.node_data} \
            --keep-root \
            --coalescent {params.coalescent} \
            --date-confidence \
            --date-inference {params.date_inference} \
            --clock-filter-iqd {params.clock_filter_iqd}
        """


rule ancestral:
    message: "Reconstructing ancestral sequences and mutations"
    input:
        tree = rules.refine.output.tree,
        alignment = rules.align.output
    output:
        node_data = "results/nt_muts_hepatitisB_{lineage}.json"
    params:
        inference = "joint"
    shell:
        """
        augur ancestral \
            --tree {input.tree} \
            --alignment {input.alignment} \
            --output-node-data {output.node_data} \
            --inference {params.inference}
        """

# rule translate:
#     message: "Translating amino acid sequences"
#     input:
#         tree = rules.refine.output.tree,
#         node_data = rules.ancestral.output.node_data,
#         reference = files.reference
#     output:
#         node_data = "results/aa_muts_hepatitisB_{lineage}.json"
#     shell:
#         """
#         augur translate \
#             --tree {input.tree} \
#             --ancestral-sequences {input.node_data} \
#             --reference-sequence {input.reference} \
#             --output {output.node_data} \
#         """


# rule clades:
#     message: "Labeling clades as specified in config/clades.tsv"
#     input:
#         tree = rules.refine.output.tree,
#         aa_muts = rules.translate.output.node_data,
#         nuc_muts = rules.ancestral.output.node_data,
#         clades = files.clades
#     output:
#         clade_data = "results/clades_hepatitisB_{lineage}.json"
#     shell:
#         """
#         augur clades \
#             --tree {input.tree} \
#             --mutations {input.nuc_muts} {input.aa_muts} \
#             --clades {input.clades} \
#             --output {output.clade_data}
#         """


rule export:
    message: "Exporting data files for for auspice"
    input:
        tree = rules.refine.output.tree,
        metadata = rules.parse.output.metadata,
        branch_lengths = rules.refine.output.node_data,
        nt_muts = rules.ancestral.output.node_data,
        # aa_muts = rules.translate.output.node_data,
        auspice_config = files.auspice_config
    output:
        auspice_json = "auspice/hepatitisB_{lineage}.json"
    shell:
        """
        export AUGUR_RECURSION_LIMIT=10000;
        augur export v2 \
            --tree {input.tree} \
            --metadata {input.metadata} \
            --node-data {input.branch_lengths} {input.nt_muts} \
            --include-root-sequence \
            --auspice-config {input.auspice_config} \
            --include-root-sequence \
            --output {output.auspice_json}
        """

rule clean:
    message: "Removing directories: {params}"
    params:
        "results ",
        "auspice"
    shell:
        "rm -rfv {params}"
