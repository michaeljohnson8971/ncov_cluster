localrules: clades, colors, recency, export, rename_legacy_clades, upload, download_masked, download


ruleorder: finalize_swiss > finalize
ruleorder: filter_cluster > subsample
ruleorder: download_masked > mask
ruleorder: download_masked > diagnostic

rule add_labels:
    message: "Remove extraneous colorings for main build and move frequencies"
    input:
        auspice_json = rules.incorporate_travel_history.output.auspice_json,
        tree = rules.refine.output.tree,
        clades = rules.clades.output.clade_data,
        mutations = rules.ancestral.output.node_data
    output:
        auspice_json = "results/{build_name}/ncov_with_accessions_and_travel_branches_and_labels.json",
    log:
        "logs/add_labels_{build_name}.txt"
    conda: config["conda_environment"]
    shell:
        """
        python3 scripts/add_labels.py \
            --input {input.auspice_json} \
            --tree {input.tree} \
            --mutations {input.mutations} \
            --clades {input.clades} \
            --output {output.auspice_json} 2>&1 | tee {log}
        """

rule finalize_swiss:
    message: "Remove extraneous colorings for main build and move frequencies"
    input:
        auspice_json = rules.add_labels.output.auspice_json,
        frequencies = rules.tip_frequencies.output.tip_frequencies_json
    output:
        auspice_json = "auspice/ncov_{build_name}.json",
        tip_frequency_json = "auspice/ncov_{build_name}_tip-frequencies.json"
    log:
        "logs/fix_colorings_{build_name}.txt"
    conda: config["conda_environment"]
    shell:
        """
        python3 scripts/fix-colorings.py \
            --input {input.auspice_json} \
            --output {output.auspice_json} 2>&1 | tee {log} &&
        cp {input.frequencies} {output.tip_frequency_json}
        """

rule extract_cluster:
    input:
        cluster = "cluster_profile/clusters/cluster_{build_name}.txt",
        alignment = "results/masked.fasta"
    output:
        cluster_sample = "results/{build_name}/sample-precluster.fasta"
    run:
        from Bio import SeqIO

        with open(input.cluster) as fh:
            cluster = set([x.strip() for x in fh.readlines()])

        seq_out = open(output.cluster_sample, 'w')
        for s in SeqIO.parse(input.alignment, 'fasta'):
            if s.id in cluster:
                SeqIO.write(s, seq_out, 'fasta')

        seq_out.close()

rule filter_cluster:
    input:
        sequences = rules.extract_cluster.output.cluster_sample,
        metadata = rules.download.output.metadata,
        include = config["files"]["include"]
    output:
        sequences = "results/{build_name}/sample-cluster.fasta"
    log:
        "logs/subsample_{build_name}_cluster.txt"
    conda: config["conda_environment"]
    shell:
        """
        augur filter \
            --sequences {input.sequences} \
            --metadata {input.metadata} \
            --include {input.include} \
            --group-by country year month \
            --sequences-per-group 900 \
            --output {output.sequences} 2>&1 | tee {log}
        """

rule download_masked:
    message: "Downloading metadata and fasta files from S3"
    output:
        sequences = "results/masked.fasta",
        diagnostics = "results/sequence-diagnostics.tsv",
        flagged = "results/flagged-sequences.tsv",
        to_exclude = "results/to-exclude.txt"
    conda: config["conda_environment"]
    shell:
        """
        aws s3 cp s3://nextstrain-ncov-private/masked.fasta.gz - | gunzip -cq > {output.sequences:q}
        aws s3 cp s3://nextstrain-ncov-private/sequence-diagnostics.tsv.gz - | gunzip -cq > {output.diagnostics:q}
        aws s3 cp s3://nextstrain-ncov-private/flagged-sequences.tsv.gz - | gunzip -cq > {output.flagged:q}
        aws s3 cp s3://nextstrain-ncov-private/to-exclude.txt.gz - | gunzip -cq > {output.to_exclude:q}
        """