class ImportController < ApplicationController
  before_action :authenticate_user!
  before_action :set_oauth_account
  before_action :set_season

  def index
    @matches = nil
    @match_count = @oauth_account.matches.in_season(@season).count
  end

  def create
    file = params[:csv]
    unless file
      flash[:alert] = 'No CSV file was provided.'
      return redirect_to(import_path(@season, @oauth_account))
    end

    table = CSV.read(file.path, headers: true, header_converters: [:downcase])
    map_ids_by_name = Map.select([:id, :name]).
      map { |map| [map.name.downcase, map.id] }.to_h
    heroes_by_name = Hero.all.map { |hero| [Hero.flatten_name(hero.name), hero] }.to_h
    @matches = []

    # Wipe existing matches this season
    @oauth_account.matches.in_season(@season).destroy_all

    prior_match = nil
    table.each do |row|
      match = @oauth_account.matches.new(rank: row['rank'].to_i, season: @season,
                                         comment: row['comment'], prior_match: prior_match,
                                         placement: false)
      if (map_name = row['map']).present?
        match.map_id = map_ids_by_name[map_name.downcase]
      end
      if (time = row['time']).present?
        match.time_of_day = time.downcase
      end
      if (day = row['day']).present?
        match.day_of_week = day.downcase
      end
      if (ally_thrower = row['ally thrower']).present?
        match.ally_thrower = ally_thrower.downcase == 'y'
      end
      if (ally_leaver = row['ally leaver']).present?
        match.ally_leaver = ally_leaver.downcase == 'y'
      end
      if (enemy_thrower = row['enemy thrower']).present?
        match.enemy_thrower = enemy_thrower.downcase == 'y'
      end
      if (enemy_leaver = row['enemy leaver']).present?
        match.enemy_leaver = enemy_leaver.downcase == 'y'
      end

      match.save

      if match.persisted? && (hero_name_str = row['heroes']).present?
        hero_names = hero_name_str.split(',')
        heroes = hero_names.map do |name|
          flat_name = Hero.flatten_name(name.strip)
          heroes_by_name[flat_name]
        end
        heroes = heroes.compact
        heroes.each { |hero| match.heroes << hero }
      end

      prior_match = if match.persisted?
        match
      end
      @matches << match
    end

    results = @matches.map(&:persisted?)
    @match_count = @oauth_account.matches.in_season(@season).count

    if @matches.empty?
      flash[:alert] = 'No matches were found in the selected file.'
      render 'import/index'
    elsif results.all?
      flash[:notice] = "Successfully imported #{@matches.size} " +
        "#{'match'.pluralize(@matches.size)} to #{@season}."
      redirect_to matches_path(@season, @oauth_account)
    elsif results.any?
      success_count = @matches.select(&:persisted?).size
      failure_count = @matches.select(&:new_record?).size
      flash[:alert] = "Imported #{success_count} #{'match'.pluralize(success_count)}, but " +
        "#{failure_count} #{'match'.pluralize(failure_count)} failed to import."
      render 'import/index'
    else
      flash[:error] = "Failed to import #{@matches.size} #{'match'.pluralize(@matches.size)}."
      render 'import/index'
    end
  end
end
