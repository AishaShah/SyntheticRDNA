require 'rbbt-util'
require 'rbbt/workflow'

Misc.add_libdir if __FILE__ == $0

#require 'rbbt/sources/SyntheticRDNA'

Workflow.require_workflow "HTSBenchmark"
Workflow.require_workflow "HTS"
module SyntheticRDNA
  extend Workflow

  dep_task :simulate_t2t, HTSBenchmark, :NEAT_simulate_DNA, :reference => Rbbt.data["T2T_rDNA45S.219_morphs.fa.gz"]

  dep :simulate_t2t
  dep_task :align_simulated_t2t, HTS, :BAM, :skip_rescore => true, :reference => Rbbt.data["T2T_rDNA45S.24_uniq_morphs.fa.gz"] do |jobname,options,dependencies|
    dep = dependencies.flatten.first
    options[:fastq1] = dep.file('output/' + jobname + '_read1.fq.gz')
    options[:fastq2] = dep.file('output/' + jobname + '_read2.fq.gz')
    {:inputs => options}
  end

  helper :load_contigs do |fasta_file|
    contigs = {}
    name_line = nil
    TSV.traverse fasta_file, :type => :array do |line|
      line.strip!
      if line.chomp.empty?
        next
      elsif line.start_with? ">"
        name_line = line
        contigs[name_line] = ""
      else
        contigs[name_line] += line.strip
      end
    end

    contigs
  end

  helper :preprocess_mutation do |contig,pad|
    pos = rand(contig.length).floor

    start = pos - pad
    eend = pos + pad
    start = 0 if start < 0

    reference = contig[pos] 
    original = contig[start..eend] 

    [pos, start, eend, reference, original]
  end

  input :reference_contigs, :file, "FASTA with reference contigs", Rbbt.data["T2T_rDNA45S.24_uniq_morphs.fa.gz"]
  input :number_of_snvs, :integer, "Number of SNV to introduce", 100
  input :number_of_ins, :integer, "Number of insertions", 20
  input :number_of_del, :integer, "Number of deletions", 20
  input :pad, :integer, "Surronding area", 100
  task :mutation_catalogue => :array do |reference_contigs,number_of_snvs,number_of_ins,number_of_del,pad|
    contigs = load_contigs reference_contigs

    snvs = number_of_snvs.times.collect do 
      contig = contigs[contigs.keys.sample]
      pos, start, eend, reference, original = preprocess_mutation contig, pad

      alt = (%w(A C T G) - [reference.upcase]).shuffle.first
      alt = alt.downcase if reference == reference.downcase
      mutated = begin
                  tmp = contig.dup
                  tmp[pos] = alt
                  tmp[start..eend] 
                end
      [original, mutated] * "=>"
    end

    ins = number_of_ins.times.collect do 
      contig = contigs[contigs.keys.sample]
      pos, start, eend, reference, original = preprocess_mutation contig, pad

      size = rand(6).to_i + 2
      alt = size.times.collect{ %w(A C T G).sample } * ""
      mutated = begin
                  tmp = contig.dup
                  tmp[pos] += alt
                  tmp[start..eend] 
                end
      [original, mutated] * "=>"
    end

    dels = number_of_del.times.collect do 
      contig = contigs[contigs.keys.sample]
      pos, start, eend, reference, original = preprocess_mutation contig, pad

      size = rand(6).to_i + 1
      mutated = begin
                  tmp = contig.dup
                  tmp[(pos..pos+size-1)] = ""
                  tmp[start..(eend-size)] 
                end
      [original, mutated] * "=>"
    end

    snvs + ins + dels
  end

  dep :mutation_catalogue
  input :reference_contigs, :file, "FASTA with reference contigs", Rbbt.data["T2T_rDNA45S.24_uniq_morphs.fa.gz"]
  input :catalogue_size, :integer, "Number of contigs to create", 144
  input :mutations_per_contig, :integer, "Number of mutations to introduce in each contig", 10
  extension "fa"
  task :contig_catalogue => :text do |reference_contigs,catalogue_size,mutations_per_contig|
    original_contigs = load_contigs reference_contigs
    mutations = step(:mutation_catalogue).load.collect{|e| e.split("=>") }

    original_contig_keys = original_contigs.keys
    catalogue_size.times.collect do |contig_number|
      contig_source = original_contig_keys.sample
      original_sequence = original_contigs[contig_source]

      selected_mutations = mutations
        .select{|ref,mut| original_sequence.include? ref }
        .sample(mutations_per_contig)

      mutated_sequence = original_sequence.dup
      mutations_per_contig.times do 
        ref, mut = mutations.select{|ref,mut| mutated_sequence.include? ref}.first
        mutated_sequence[ref] = mut
      end

      name = ">synth_#{contig_number}.#{contig_source[1..-1]}"
      [name, mutated_sequence] * "\n"
    end * "\n"
  end

  dep :contig_catalogue, :jobname => "SharedCatalogue"
  input :sample_contigs, :integer, "Number of sample contigs", 200
  extension "fa.gz"
  task :sample_fasta => :text do |sample_contigs|
    catalogue = load_contigs step(:contig_catalogue).path
    catalogue_keys = catalogue.keys
    txt = sample_contigs.times.collect do |sample_contig|
      base = catalogue_keys.sample
      sequence = catalogue[base]
      name = ">sample_#{sample_contig}.#{base[1..-1]}"
      [name, sequence] * "\n"
    end * "\n"
    tmpfile = file('tmp.fa')
    Open.write(tmpfile, txt + "\n")
    CMD.cmd("bgzip #{tmpfile}")
    Open.mv tmpfile + '.gz', self.tmp_path
    Open.rm_rf files_dir
    nil
  end

  dep :sample_fasta
  dep_task :simulate_sample, HTSBenchmark, :NEAT_simulate_DNA, :reference => :sample_fasta, :depth => 50

  input :numer_of_samples, :integer, "How many samples to generate", 100
  dep :simulate_sample do |jobname,options|
    options[:numer_of_samples].to_i.times.collect do |i|
      {:jobname => "Sample#{i}"}
    end
  end
  task :simulate_sample_cohort => :array do
    dependencies.collect{|dep| dep.load }.flatten
  end

end

#require 'SyntheticRDNA/tasks/basic.rb'

#require 'rbbt/knowledge_base/SyntheticRDNA'
#require 'rbbt/entity/SyntheticRDNA'

