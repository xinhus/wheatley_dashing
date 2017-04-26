require "octokit"
require "httparty"

module Wheatley
  @access_token = ENV['GITHUB_ACCESS_TOKEN']
  @mobiles_repositories = ['ebanx/ego-ios', 'ebanx/ego-android', 'ebanx/ios', 'ebanx/android']
  @development_repositories = @mobiles_repositories + ['ebanx/woocommerce-gateway-ebanx']
  @repos = ['ebanx/woocommerce-gateway-ebanx', 'ebanx/pay', 'ebanx/everest', 'ebanx/account', 'ebanx/knox', 'ebanx/gandalf', 'ebanx/ego'] + @mobiles_repositories

  class << self
    attr_accessor :access_token, :repos
  end

  def self.run()
    raise "GITHUB_ACCESS_TOKEN environment variable must be set" unless @access_token

    client = Wheatley::Client.new access_token

    result = []

    date = Date.new(2017, 4, 10);
    repos.each do |repo|

      puts "Repo " + repo

      bases = if @development_repositories.include? repo then ['develop'] else ['master'] end
      bases = ['staging-v2', 'master'] if repo == 'ebanx/everest'

      bases.each do |base|
        prs = client.get_prs_per_day(date: date, repo: repo, base: base)

        prs.each do |pr|
          hasTest = client.pr_has_test2? pr
          hasException = client.pr_is_exception? pr
          hasQuality = client.pr_is_quality? pr

          print "##\t" + pr[:head][:repo][:name] +
                    "\t" + pr[:html_url] +
                    "\t" + pr[:user][:login] +
                    "\t" + pr[:title] +
                    "\t#{hasTest}" +
                    "\t#{hasException}" +
                    "\t#{hasQuality}" +
                    "\n"

          result.push({
                          :repo =>  pr[:head][:repo][:name],
                          :url => pr[:html_url],
                          :author => pr[:user][:login],
                          :title => pr[:title],
                          :avatar => pr[:user][:avatar_url],
                          :merged_at => pr[:merged_at],
                          :hasTests? => hasTest,
                          :isExceptedFromTesting => hasException,
                          :hasQualitySeal? => hasQuality
                      })
        end

      end
    end

    return result
  end

  class Client
    def initialize(access_token)
      @access_token = access_token
      @client ||= Octokit::Client.new(:access_token => access_token)
    end

    def get_prs_per_day(date: Date.today-1, repo:'', base: 'master')
      print "prs for " + repo + "\n"
      results = []
      prs = [1]
      page = 1

      while results.nil? or prs.count != 0
        prs = @client.pull_requests(repo, state: 'closed', base: base, direction: 'desc', page: page, sort: 'merged')

        prs.each do |pr|
          is_merged = pr.merged_at
          if (is_merged != nil)
            results << pr if pr[:updated_at].to_date >= date and is_merged
            return results if pr[:updated_at].to_date < date
          end
        end

        page += 1
      end

      results
    end

    def pr_has_test2? pr
      response = HTTParty.get(pr['url'], :headers => {
          "Authorization" => "token #{@access_token}",
          "Accept" => "application/vnd.github.v3.diff",
          "User-Agent" => "Wheatley"
      })

      pr_diff = response.body

      begin
        if /^\+.*Test/.match pr_diff || pr_has_end_to_end?(pr)
          true
        else
          false
        end
      rescue
      end
    end

    def pr_is_exception? pr
      labels = pr_labels(pr)

      labels.each do |label|
        return true if label[:name] == "exception"
        return true if label[:name] == "LGTM (no tests needed)"
        return true if label[:name] == "no tests needed"
      end

      false
    end

    def pr_has_end_to_end? pr
      labels = pr_labels(pr)

      labels.each do |label|
        return true if label[:name] == "LGTM (end to end tested)"
      end

      false
    end

    def pr_is_quality? pr

      labels = pr_labels(pr)

      labels.each do |label|
        return true if label[:name] == "Quality"
        return true if label[:name] == "quality-improvement"
        return true if label[:name] == "quality improvement"
      end

      false
    end

    def pr_labels (pr)
      begin
        response = @client.issue(pr[:head][:repo][:full_name], pr[:number])[:labels]
      rescue
        return [{:name => "Quality"}]
      end
      response
    end
  end
end

def get_team_by_author(author)
  if ['kalecser', 'jejung', 'daltones', 'danxexe', 'andreribas', 'erichnascimento', 'manuerumx'].include? author
    return 'Payment Processing'
  end

  if ['miguelxpn', 'frop', 'ijda3', 'danielnass', 'cezarlz', 'cristopher-rodrigues', 'IneedRock', 'Jonatan-Korello', 'williandricken', 'gpressutto5', 'SparK-Cruz', 'guilhermepiovesan'].include? author
    return 'Merchant Product / SMB'
  end

  if ['brunoberte', 'fabioaalves', 'fariajp' , 'geicyane', 'LuisMaleski', 'rihjsantos', 'thiagocordeiro', 'Valforte', 'vinivf', 'leandrofinger'].include? author
    return 'Finance'
  end

  if ['diogenes', 'jonhkr', 'alexalth', 'Klockner', 'celsofabri', 'fariasdiego', 'brunob182'].include? author
    return 'End User - Web / MKT'
  end

  if ['leandroBorgesFerreira', 'ssamumobi', 'guitcastro', 'cocuroci', 'mikhaelt', 'gustavomobiletouch', 'Leowanp'].include? author
    return 'End User - Mobile'
  end

  return 'Unknown team'
end

def get_quality_prs (prs)
  prs.select {|pr| pr[:hasQualitySeal?]}
end

def get_test_prs (prs)
  prs.select {|pr| pr[:hasTests?]}
end

def get_test_eligible_prs (prs)
  prs.select {|pr| !pr[:isExceptedFromTesting]}
end

def calculate_top_quality_devs (prs)
    get_quality_prs(prs)
        .group_by {|pr| pr[:author]}
        .sort_by  {|author_prs| - author_prs[1].length }
        .take(5)
        .map {|author_prs| {label: author_prs[0], value: author_prs[1].length}}
end

def calculate_top_quality_teams (prs)
  get_quality_prs(prs)
      .group_by {|pr| get_team_by_author(pr[:author])}
      .sort_by  {|author_prs| - author_prs[1].length }
      .take(5)
      .map {|author_prs| {label: author_prs[0], value: author_prs[1].length}}
end

def calculate_top_test_teams (prs)
  prs
      .group_by {|pr| get_team_by_author(pr[:author])}
      .map {|prs_by_repo| {repo: prs_by_repo[0], tests_percentage: calculate_tests_percentage(prs_by_repo[1])}}
      .sort_by { |tests_by_repo| - tests_by_repo[:tests_percentage] }
      .take(5)
      .map {|tests_by_repo| {:label => tests_by_repo[:repo], :value => tests_by_repo[:tests_percentage]}}

end

def calculate_quality_percentage(prs)
  total_pr_count =    prs.length
  quality_prs_count = get_quality_prs(prs).length

  ((quality_prs_count.to_f / total_pr_count.to_f) * 100).round
end

def calculate_tests_percentage(prs)
  eligible_pr_count = get_test_eligible_prs(prs).length
  test_prs_count = get_test_prs(prs).length

  ((test_prs_count.to_f / eligible_pr_count.to_f) * 100).round
end

def get_picture_last_quality_pr(prs)
  get_quality_prs(prs)
  .sort_by { |pr| pr[:merged_at] }
  .last[:avatar]
end

def get_lowest_five_test_percentage_per_repository(prs)
  prs
      .group_by {|pr| pr[:repo]}
      .map {|prs_by_repo| {repo: prs_by_repo[0], tests_percentage: calculate_tests_percentage(prs_by_repo[1])}}
      .sort_by { |tests_by_repo| tests_by_repo[:tests_percentage] }
      .take(5)
      .map {|tests_by_repo| {:label => tests_by_repo[:repo], :value => tests_by_repo[:tests_percentage]}}

end

SCHEDULER.every '10m', :first_in => 0 do |job|

  result = Wheatley.run

  send_event('total_prs',  current: result.length)
  send_event('top_quality_devs', items: calculate_top_quality_devs(result))
  send_event('top_quality_teams', items: calculate_top_quality_teams(result))
  send_event('top_tests_teams', items: calculate_top_test_teams(result))
  send_event('quality_percentage', value: calculate_quality_percentage(result))
  send_event('test_percentage', value: calculate_tests_percentage(result))
  send_event('last_quality_pr_photo', image: get_picture_last_quality_pr(result))
  send_event('test_percentage_per_repository', items: get_lowest_five_test_percentage_per_repository(result))

end
