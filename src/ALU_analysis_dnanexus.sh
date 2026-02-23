#!/bin/bash
# Exit on error, print each command as it runs
set -e -x -o pipefail

# Download all inputs specified in dxapp.json
dx-download-all-inputs --parallel

# Make scratch directory for docker output and named output folders for DNAnexus
mkdir -p /home/dnanexus/scratch
mkdir -p /home/dnanexus/reference
mkdir -p ~/out/clusters_txt
mkdir -p ~/out/vcf_gz
mkdir -p ~/out/alu_vcf
mkdir -p ~/out/alu_analysis_csv
mkdir -p ~/out/alu_analysis_high_confidence_csv

# Download Docker image using hardcoded file ID
scramble_docker_file_id=project-J1g3b9Q0BfbvfX94Y8xzx0zg:file-J6FYk9Q0BfbyzYfPyPYgX002
dx download ${scramble_docker_file_id}

# Get the filename and extract the image name from the tar manifest
scramble_docker_image_file=$(dx describe ${scramble_docker_file_id} --name)
echo "Docker image file: ${scramble_docker_image_file}"
scramble_docker_image_file=${scramble_docker_image_file//:/-}
scramble_docker_image_name=$(tar xfO "${scramble_docker_image_file}" manifest.json | sed -E 's/.*"RepoTags":\["?([^"]*)"?.*/\1/')
echo "Docker image name: ${scramble_docker_image_name}"

# Load the Docker image
docker load < /home/dnanexus/"${scramble_docker_image_file}"

# Extract sample ID from BAM filename
sample_id=$(basename ${bam_name} | grep -oP 'NGS[^_]+_\d+')
echo "Sample ID: ${sample_id}"

# Unpack reference genome tar.gz
tar -xzf ${reference_tar_path} -C /home/dnanexus/reference/

# Find the reference fasta
ref_fa=$(find /home/dnanexus/reference -name "*.fa" -o -name "*.fasta" | head -n 1)
echo "Reference FASTA: ${ref_fa}"

# Copy BAM/BAI to sample ID filename for use inside container
cp ${bam_path} /home/dnanexus/${sample_id}.bam
cp ${bai_path} /home/dnanexus/${sample_id}.bai

# Build optional arguments
bed_mount=""
bed_arg=""
if [ -n "${bed_path}" ]; then
    bed_mount="-v ${bed_path}:/app/data/regions.bed"
    bed_arg="--bed /app/data/regions.bed"
fi

verbose_arg=""
if [ "${verbose}" = "true" ]; then
    verbose_arg="--verbose"
fi

# Run the Scramble Docker container
docker run --rm \
    -v /home/dnanexus/${sample_id}.bam:/app/data/${sample_id}.bam \
    -v /home/dnanexus/${sample_id}.bai:/app/data/${sample_id}.bai \
    -v ${ref_fa}:/app/data/reference.fa \
    -v ${ref_fa}.fai:/app/data/reference.fa.fai \
    -v ${ref_fa}.nhr:/app/data/reference.fa.nhr \
    -v ${ref_fa}.nin:/app/data/reference.fa.nin \
    -v ${ref_fa}.nsq:/app/data/reference.fa.nsq \
    -v /home/dnanexus/scratch:/app/output \
    ${bed_mount} \
    ${scramble_docker_image_name} \
    --bam /app/data/${sample_id}.bam \
    --bai /app/data/${sample_id}.bai \
    --window ${window} \
    --polyA_window ${polyA_window} \
    --threshold ${threshold} \
    --min_polyA_len ${min_polyA_len} \
    --merge_gap ${merge_gap} \
    --proximity ${proximity} \
    ${bed_arg} \
    ${verbose_arg}

# Copy outputs to named DNAnexus output folders
cp /home/dnanexus/scratch/${sample_id}.clusters.txt           ~/out/clusters_txt/
cp /home/dnanexus/scratch/${sample_id}.vcf.gz                 ~/out/vcf_gz/

# ALU VCF name depends on whether a BED file was provided
if [ -n "${bed_path}" ]; then
    cp /home/dnanexus/scratch/${sample_id}_specified_region_ALU_ins.vcf ~/out/alu_vcf/
else
    cp /home/dnanexus/scratch/${sample_id}_ALU_ins.vcf ~/out/alu_vcf/
fi

cp /home/dnanexus/scratch/${sample_id}_ALU_analysis.csv       ~/out/alu_analysis_csv/
cp /home/dnanexus/scratch/${sample_id}_ALU_analysis_high_confidence.csv ~/out/alu_analysis_high_confidence_csv/

# Upload all outputs
dx-upload-all-outputs --parallel