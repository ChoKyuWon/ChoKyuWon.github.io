# frozen_string_literal: true

# Generates one page per entry in _data/papers.yml at /publications/<key>/.
#
# Each paper gets its own indexable URL whose <title> is the paper title, rendered
# with _layouts/paper.liquid. _includes/metadata.liquid adds the Google Scholar
# citation_* meta tags and ScholarlyArticle structured data for these pages.
module PaperPages
  class Generator < Jekyll::Generator
    safe true
    priority :high

    def generate(site)
      Array(site.data["papers"]).each do |paper|
        site.pages << PaperPage.new(site, paper)
      end
    end
  end

  class PaperPage < Jekyll::PageWithoutAFile
    def initialize(site, paper)
      super(site, site.source, File.join("publications", paper["key"]), "index.html")
      self.content = ""
      data.merge!(
        "layout" => "paper",
        "title" => paper["title"],
        "description" => description_for(paper),
        "paper" => paper
      )
    end

    private

    def description_for(paper)
      return squish(paper["abstract"]) if paper["abstract"]

      authors = squish(paper["authors"].to_s.gsub(%r!<[^>]+>!, ""))
      "#{authors}. #{squish(paper["venue"])}, #{paper["year"]}."
    end

    def squish(text)
      text.to_s.gsub(%r!\s+!, " ").strip
    end
  end
end
