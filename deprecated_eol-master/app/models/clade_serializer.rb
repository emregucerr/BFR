class CladeSerializer
  class << self
    # e.g.:
    # CladeSerializer.store_clade_starting_from(1) => Animalia (3_888_534) (don't hold your breath)
    # CladeSerializer.store_clade_starting_from(694) => Chordata (718_192)
    # CladeSerializer.store_clade_starting_from(2774383) => Vertebrata (213_935)
    # CladeSerializer.store_clade_starting_from(12094272) => Gnathostomata (209_386)
    # CladeSerializer.store_clade_starting_from(4712200) => Tetrapoda (135_778)
    # CladeSerializer.store_clade_starting_from(1642) => Mamalia (88_165)
    # CladeSerializer.store_clade_starting_from(7662) => Carnivora (10_369)
    # CladeSerializer.store_clade_starting_from(7665) => Procyonidae (695)

    def store_clade_starting_from(pid, options = {})
      part = 0
      # e.g.:
      # grep '^  \"id\":' public/store-clade-1642-part77.json | tail -n 1
      # > log/serial.log ; nohup bundle exec rails runner -e production
      # "CladeSerializer.store_clade_starting_from(1642, last_part: 77,
      # last_id: 115681)" > log/serial.log &
      if options[:last_part]
        part = options[:last_part]
      end
      batch_size = 50
      stored = 0
      taxa = TaxonConceptsFlattened.descendants_of(pid)
      if options[:last_id]
        taxa = taxa.where(["taxon_concept_id > ?", options[:last_id]])
      end
      batch = []
      EOL.log("CLS: Storing clade starting from Page ID #{pid}...", prefix: "{")

      clade_page = nil
      taxa.find_each(batch_size: batch_size) do |descendant_page|
        tid = descendant_page[:taxon_concept_id]
        data = PageSerializer.get_page_data(tid)
        batch << begin
          JSON.pretty_generate(data)
        rescue
          EOL.log("CLS: There was an error writing page #{tid}, skipping...", prefix: "!")
          EOL.log("#{data.inspect}", prefix: "=")
          "{\"_comment\": \"There was an error processing page #{tid}.\"}"
        end
        if batch.size >= batch_size
          stored += flush(pid, batch, part += 1)
          batch = []
        end
      end
      EOL.log("CLS: Done (#{stored} pages from Page ID #{pid}).", prefix: "}")
    end

    def flush(pid, batch, part)
      file_name = Rails.root.join("public", "store-clade-#{pid}-part#{part}.json").to_s
      EOL.log("CLS: Flushing #{batch.size} pages into #{file_name}...", prefix: "..")
      File.open(file_name, "wb") do |file|
        file.write("[\n")
        file.write(batch.join(",\n"))
        file.write("\n]\n")
      end
      File.chmod(0644, file_name)
      batch.size
    end
  end
end
