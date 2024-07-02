class TraitSet
  attr_accessor :points, :glossary, :traits, :sources, :sources_map, :taxa, :id

  # YOU *NEED* TO IMPLEMENT #initialize and #populate ! See PageTraits for an
  # example.

  def blank?
    populate
    traits.blank?
  end

  def predicates
    populate
    @predicates ||= Set.new(traits.map(&:predicate_uri).compact).
      sort_by(&:position)
  end

  def predicate_count
    populate
    @predicate_count ||= predicates.count
  end

  def categories
    return @categories if @categories
    populate
    @categories = Set.new(traits.flat_map(&:categories)).
      to_a.sort_by(&:view_order)
    @categories
  end

  def categories_need_other?
    populate
    @need_other ||= traits.any? { |t| t.categories.empty? }
  end

  # NOTE: Sorry this is complex, but: there are a lot of considerations for
  # sort!
  def traits_by_category(category)
    populate
    subset = if category == :other
      traits.select { |trait| trait.categories.empty? }
    else
      traits.select { |trait| trait.categories.include?(category) }
    end
    subset.sort_by do |trait|
      predicate = trait.predicate_name.try(:downcase)
      value_label = trait.value_name.try(:downcase)
      sex_sort = trait.sex_name || 255.chr
      stage_sort = trait.life_stage_name || ''
      # NOTE: it's possible to have more than one, but we only care about first:
      stats_sort = trait.statistical_method? ?
        trait.statistical_methods.first.position : 65000
      [ trait.predicate_uri.position, predicate, sex_sort,
        stats_sort, stage_sort, value_label ]
    end
  end

  # TODO: I forget whether KnownUris can be excluded from the overview. Check. I
  # don't think so (I think we rely on sort), so I haven't implemented that.
  def traits_overview
    populate
    uris = predicates[0..OverviewTraits.max_rows]
    overview = traits.select { |trait| uris.include?(trait.predicate_uri) &&
      ! trait.excluded? }.group_by(&:predicate_uri)
    overview.keys.each do |uri|
      overview[uri] = OverviewTraits.new(overview[uri])
    end
    overview
  end

  def build_sources
    source_ids = @traits.map { |trait| trait.source_id }.compact.uniq
    @sources = Resource.where(id: source_ids).includes(:content_partner)
    @sources_map = {}
    source_ids.each { |id| @sources_map[id] = @sources.find { |s| s.id == id } }
  end
end
