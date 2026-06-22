#!/bin/bash
# Exit on error, print each command as it runs
set -e -x -o pipefail

# Download all inputs specified in dxapp.json
dx-download-all-inputs --parallel

# Make output directory for docker output and named output folders for DNAnexus
mkdir -p /home/dnanexus/reference
mkdir -p /home/dnanexus/output
mkdir -p ~/out/clusters_txt
mkdir -p ~/out/vcf_gz
mkdir -p ~/out/alu_vcf
mkdir -p ~/out/alu_analysis_high_confidence_csv
mkdir -p ~/out/sequence_search_out

# Download Docker image using hardcoded file ID
alu_docker_file_id=project-J1g3b9Q0BfbvfX94Y8xzx0zg:file-J8pb9v00BfbqYXFvbfZjB9G4
dx download ${alu_docker_file_id}

# Get the filename and extract the image name from the tar manifest
alu_docker_image_file=$(dx describe ${alu_docker_file_id} --name)
echo "Docker image file: ${alu_docker_image_file}"
alu_docker_image_file=${alu_docker_image_file//:/-}
alu_docker_image_name=$(tar xfO "${alu_docker_image_file}" manifest.json | sed -E 's/.*"RepoTags":\["?([^"]*)"?.*/\1/')
echo "Docker image name: ${alu_docker_image_name}"

# Load the Docker image
docker load < /home/dnanexus/"${alu_docker_image_file}"

# remove docker image file once image is loaded
rm /home/dnanexus/"${alu_docker_image_file}"

# Unpack reference genome tar.gz
tar -xzf ${reference_tar_path} -C /home/dnanexus/reference/
ls -la /home/dnanexus/reference/

# Find the reference fasta
ref_fa=$(find /home/dnanexus/reference -name "*.fa" -o -name "*.fasta" | head -n 1)
echo "Reference FASTA: ${ref_fa}"
REF_DIR=$(dirname "$ref_fa")

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

# Run the ALU_analysis docker container
docker run --rm \
  -e DX_SECURITY_CONTEXT="$DX_SECURITY_CONTEXT" \
  -e DX_APISERVER_HOST="$DX_APISERVER_HOST" \
  -e DX_APISERVER_PROTOCOL="$DX_APISERVER_PROTOCOL" \
  -e DX_APISERVER_PORT="$DX_APISERVER_PORT" \
  -v $(realpath $REF_DIR/hs37d5.fa):/app/data/reference.fa \
  -v $(realpath $REF_DIR/hs37d5.fa.fai):/app/data/reference.fa.fai \
  -v $(realpath $REF_DIR/hs37d5.fa.nhr):/app/data/reference.fa.nhr \
  -v $(realpath $REF_DIR/hs37d5.fa.nin):/app/data/reference.fa.nin \
  -v $(realpath $REF_DIR/hs37d5.fa.nsq):/app/data/reference.fa.nsq \
  -v $(pwd)/output:/app/output \
  "$alu_docker_image_name" \
  --dx_project_id "$dx_project_id"

# Copy outputs to named DNAnexus output folders
cp /home/dnanexus/output/*.clusters.txt           ~/out/clusters_txt/
cp /home/dnanexus/output/*.vcf.gz                 ~/out/vcf_gz/
for f in /home/dnanexus/output/*_output_*.txt; do
    [ -f "$f" ] && cp "$f" ~/out/sequence_search_out/
done

# ALU VCF name depends on whether a BED file was provided
if [ -n "${bed_path}" ]; then
    cp /home/dnanexus/output/*_specified_region_ALU_ins.vcf ~/out/alu_vcf/
else
    cp /home/dnanexus/output/*_ALU_ins.vcf ~/out/alu_vcf/
fi

for f in /home/dnanexus/output/*_ALU_analysis_high_confidence.csv; do
    [ -f "$f" ] && cp "$f" ~/out/alu_analysis_high_confidence_csv/
done

# Upload all outputs
dx-upload-all-outputs --parallel