namespace :eol do
  namespace :data do
    
    desc 'Creates hierachy_entries.yml for testing purposes.'
    task :generate_hierarchy_entries_yml => :environment do
      sql = "SELECT * FROM %s"
      type = 'hierarchy_entries'
      
      # Load template data into the database
      HierarchyEntry.destroy_all
      t_hash = YAML::load(ERB.new(File.read(Rails.root.join('spec', 'fixtures', "#{type}.yml.erb"))).result)
      t_hash.each do |label, data|
        he = HierarchyEntry.new(data)
        he.id = data['id']
        he.save!
      end
      
      # Create a lookup hash of id => label to preserve the original labels.
      h = Hash.new
      t_hash.keys.each do |label|
        h[t_hash[label]['id'].to_i] = label
      end
      f = Rails.root.join("spec", "fixtures", "#{type}.yml")
      begin
        # Delete the generated file, if it exists.
        File.delete f
      rescue
        # Didn't exist.
      end

      # Create our nested set data as appropriate.
      EOL::Data.make_all_nested_sets

      # Write the actual .yml file.
      File.open(f, 'w') do |file| 
        file.write "# This file is generated! Modify the template and regenerate, not this file! -Preston\n"
        data =  HierarchyEntry.connection.select_all(sql % type) 
        
        yaml = data.inject({}) { |hash, record| 
          hash[h[record['id'].to_i]] = record
          hash
        }.to_yaml
        puts
        file.write yaml
      end
    end
    
    
  end
end
