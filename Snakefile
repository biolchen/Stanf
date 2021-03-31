import pandas as pd

samples = pd.read_table('PRJNA274006.txt')
samples['sp'] = samples['scientific_name'].values
samples.replace({'sp' : {'Homo sapiens' : 'human',
                         'Mus musculus' : 'mouse'}},
                inplace=True)
samples['cells'] = samples.sample_title.str.split('-').str[1]
batch = samples.drop_duplicates(subset=['sp', 'cells'])

genomes = {'human' : '/labs/mmdavis/chen/ATAC-seq1/ref/hg19/genome',
           'mouse' : '/mnt/reference/mus_musculus/ucsc/mm10/hisat2_index/mm10_sm'}

gsizes = {'human' : 'hs',
          'mouse' : 'mm'}

csizes = {'human' : 'hg38.chrom.sizes',
          'mouse' : 'mm10.chrom.sizes'}

rule all:
    input:
        list(samples['sp'] + '/' + samples['cells'] + '/trim_fq/' + samples['run_accession'] + '_r1.fq.gz'),
        list(samples['sp'] + '/' + samples['cells'] + '/trim_fq/' + samples['run_accession'] + '_r2.fq.gz'),
        list(samples['sp'] + '/' + samples['cells'] + '/hisat2_mapped/' + samples['run_accession'] + '_f2q30.bam'),
        list(samples['sp'] + '/' + samples['cells'] + '/hisat2_log/' + samples['run_accession'] + '_aln_sum.txt'),
        list(samples['sp'] + '/' + samples['cells'] + '/picard_bam/' + samples['run_accession'] + '_f2q30_pmd.bam'),
        list(samples['sp'] + '/' + samples['cells'] + '/picard_bam/' + samples['run_accession'] + '_f2q30_pmd.bam.bai'),
        list(samples['sp'] + '/' + samples['cells'] + '/picard_log/' + samples['run_accession'] + '_f2q30_pmd.out'),
        list(samples['sp'] + '/' + samples['cells'] + '/isize_hist/' + samples['run_accession'] + '_isize.hist'),
        list(batch['sp'] + '/' + batch['cells'] + '/bam_file_list.txt'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/f2q30_merged.bam'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/f2q30_merged_pmd.bam'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/f2q30_merged_pmd.out'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/aggregated_scATAC_peaks.narrowPeak'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/aggregated_scATAC_peaks.xls'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/aggregated_scATAC_summits.bed'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/aggregated_scATAC_treat_pileup.bdg'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/aggregated_scATAC_control_lambda.bdg'),
        list(batch['sp'] + '/' + batch['cells'] + '/aggregate/aggregated_scATAC_treat_pileup.bw'),
        list(samples['sp'] + '/' + samples['cells'] + '/count/' + samples['run_accession'] + '.count'),
        'qc_metrics/dup_level.txt',
        'qc_metrics/mapping_rate.txt',
        'qc_metrics/mt_content.txt',
        'qc_metrics/sequencing_depth.txt',
        'qc_metrics/uniq_nuc_frags.txt',
        'qc_metrics/library_size.txt',
        'qc_metrics/frip.txt',
        'qc_metrics/frac_open.txt'

rule modules:
    shell:
        '''
	module load MACS2;
        module load python/2.7;
	module load cutadapt;
	'''

rule cutadapt:
    input:
        r1='H1ESC2/{run_accession}_pass_1.fastq',
        r2='H1ESC2/{run_accession}_pass_2.fastq'
    output:
        r1='{sp}/{cells}/trim_fq/{run_accession}_r1.fq.gz',
        r2='{sp}/{cells}/trim_fq/{run_accession}_r2.fq.gz'
    log:
        out='logs/cutadapt/{sp}/{cells}/{run_accession}.out',
        err='logs/cutadapt/{sp}/{cells}/{run_accession}.err'
    shell:
	'''cutadapt \
	-f fastq \
	-m 25 \
	-u -1 \
	-U -1 \
	-a CTGTCTCTTATACACATCTCCGAGCCCACGAGACNNNNNNNNATCTCGTATGCCGTCTTCTGCTTG \
	-A CTGTCTCTTATACACATCTGACGCTGCCGACGANNNNNNNNGTGTAGATCTCGGTGGTCGCCGTATCATT \
	-o {output.r1} -p {output.r2} \
            {input.r1} \
            {input.r2} \
            1> {log.out}
            2> {log.err}
        '''

rule hisat2:
    input:
        r1='{sp}/{cells}/trim_fq/{run_accession}_r1.fq.gz',
        r2='{sp}/{cells}/trim_fq/{run_accession}_r2.fq.gz'
    params:
        idx=lambda wildcards: genomes[wildcards.sp]
    output:
        bam='{sp}/{cells}/hisat2_mapped/{run_accession}_f2q30.bam',
        stats='{sp}/{cells}/hisat2_log/{run_accession}_aln_sum.txt'
    threads: 4
    shell:
        'module load hisat2;'
	'module load samtools/1.yy8'
	''' hisat2 \
            -X 2000 \
            -p {threads} \
            --no-spliced-alignment \
            -x {params.idx} \
            -1 {input.r1} \
            -2 {input.r2} \
            --summary-file {output.stats} | \
            samtools view -ShuF 4 -f 2 -q 30 - | \
            samtools sort - -T {wildcards.run_accession}_tmp -o {output.bam}
        '''

rule spicard:
    input:
        '{sp}/{cells}/hisat2_mapped/{run_accession}_f2q30.bam',
    output:
        bam='{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam',
        met='{sp}/{cells}/picard_log/{run_accession}_f2q30_pmd.out',
    log:
        'logs/spicard/{sp}/{cells}/{run_accession}.log'
    shell:
        ''' java -jar -Xmx4g \
            /labs/mmdavis/chen/tools/picard.jar \
            MarkDuplicates \
            INPUT={input} \
            OUTPUT={output.bam} \
            REMOVE_DUPLICATES=true \
            ASSUME_SORTED=true \
            METRICS_FILE={output.met} \
            2> {log}
        '''

rule index:
    input:
        '{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam'
    output:
        '{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam.bai'
    shell:
        ''' samtools index {input}
        '''

rule isize:
    input:
        '{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam'
    output:
        '{sp}/{cells}/isize_hist/{run_accession}_isize.hist'
    shell:
        """ samtools view {input} | \
            sed '/chrM/d' | \
            awk '$9>0' | \
            cut -f 9 | sort | uniq -c | \
            sort -b -k2,2n | \
            sed -e 's/^[ \t]*//' > {output}
        """

rule list_bam:
    input:
        expand('{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam', zip,
               sp=samples['sp'],
               cells=samples['cells'],
               run_accession=samples['run_accession'])
    output:
        expand('{sp}/{cells}/bam_file_list.txt', zip,
                sp=batch['sp'],
                cells=batch['cells'])
    shell:
        ''' scripts/list_bam.sh
        '''

rule merge:
    input:
        '{sp}/{cells}/bam_file_list.txt'
    output:
        '{sp}/{cells}/aggregate/f2q30_merged.bam'
    shell:
        ''' samtools merge -b {input} {output}
        '''

rule mpicard:
    input:
        '{sp}/{cells}/aggregate/f2q30_merged.bam'
    output:
        bam='{sp}/{cells}/aggregate/f2q30_merged_pmd.bam',
        met='{sp}/{cells}/aggregate/f2q30_merged_pmd.out'
    shell:
        ''' java -jar -Xmx8g \
            /home/ubuntu/picard_2.17.10/picard.jar \
            MarkDuplicates \
            INPUT={input} \
            OUTPUT={output.bam} \
            REMOVE_DUPLICATES=true \
            ASSUME_SORTED=true \
            METRICS_FILE={output.met}
        '''

rule macs2:
    input:
        '{sp}/{cells}/aggregate/f2q30_merged_pmd.bam'
    params:
        gs=lambda wildcards: gsizes[wildcards.sp]
    output:
        '{sp}/{cells}/aggregate/aggregated_scATAC_peaks.narrowPeak',
        '{sp}/{cells}/aggregate/aggregated_scATAC_peaks.xls',
        '{sp}/{cells}/aggregate/aggregated_scATAC_summits.bed',
        '{sp}/{cells}/aggregate/aggregated_scATAC_treat_pileup.bdg',
        '{sp}/{cells}/aggregate/aggregated_scATAC_control_lambda.bdg'
    log:
        'logs/macs2/{sp}/{cells}/{wildcards.cells}_macs2.out'
    shell:
        ''' macs2 callpeak -t {input} \
            -g {params.gs} \
            -f BAM \
            -q 0.01 \
            --nomodel \
            --shift -100 \
            --extsize 200 \
            --keep-dup all \
            -B --SPMR \
            --outdir {wildcards.sp}/{wildcards.cells}/aggregate \
            -n aggregated_scATAC \
            2> {log}
        '''

rule bigwig:
    input:
        bdg='{sp}/{cells}/aggregate/aggregated_scATAC_treat_pileup.bdg',
        cs=lambda wildcards: csizes[wildcards.sp]
    output:
        '{sp}/{cells}/aggregate/aggregated_scATAC_treat_pileup.bw'
    shell:
        ''' bdg2bw {input}
        '''

rule count:
    input:
        peak='{sp}/{cells}/aggregate/aggregated_scATAC_peaks.narrowPeak',
        bam='{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam'
    output:
        '{sp}/{cells}/count/{run_accession}.count'
    shell:
        ''' coverageBed \
            -a {input.peak} \
            -b {input.bam} | \
            cut -f 4,11 > {output}
        '''

rule basicQc:
    input:
        expand('{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam', zip,
               sp=samples['sp'], cells=samples['cells'],
               run_accession=samples['run_accession']),
        expand('{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam.bai', zip,
               sp=samples['sp'], cells=samples['cells'],
               run_accession=samples['run_accession']),
        expand('{sp}/{cells}/hisat2_log/{run_accession}_aln_sum.txt', zip,
               sp=samples['sp'],
               cells=samples['cells'],
               run_accession=samples['run_accession'])
    output:
        'qc_metrics/dup_level.txt',
        'qc_metrics/mapping_rate.txt',
        'qc_metrics/mt_content.txt',
        'qc_metrics/sequencing_depth.txt',
        'qc_metrics/uniq_nuc_frags.txt',
        'qc_metrics/library_size.txt'
    shell:
        ''' scripts/get_dup_level.sh
            scripts/get_depth_mr.sh
            scripts/get_ufrags_mt.sh
            scripts/get_lib_size.sh
        '''

rule frip:
    input:
        expand('{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam', zip,
               sp=samples['sp'], cells=samples['cells'],
               run_accession=samples['run_accession']),
        expand('{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam.bai', zip,
               sp=samples['sp'], cells=samples['cells'],
               run_accession=samples['run_accession']),
        expand('{sp}/{cells}/aggregate/aggregated_scATAC_peaks.narrowPeak', zip,
               sp=batch['sp'], cells=batch['cells'])
    output:
        'qc_metrics/frip.txt'
    shell:
        ''' scripts/get_frip.sh
        '''

rule fracOpen:
    input:
        expand('{sp}/{cells}/picard_bam/{run_accession}_f2q30_pmd.bam', zip,
               sp=samples['sp'], cells=samples['cells'],
               run_accession=samples['run_accession']),
        expand('{sp}/{cells}/aggregate/aggregated_scATAC_peaks.narrowPeak', zip,
               sp=batch['sp'], cells=batch['cells'])
    output:
        'qc_metrics/frac_open.txt'
    shell:
        ''' scripts/get_frac_open.sh
        '''

