---
layout: page
permalink: /publications/
title: publications
description: Publications in reverse chronological order.
nav: true
nav_order: 2
---

<!-- _pages/publications.md — rendered from _data/papers.yml -->

<div class="publications">
{%- assign years = site.data.papers | map: "year" | uniq | sort | reverse -%}
{%- for year in years -%}
  <h2 class="year">{{ year }}</h2>
  <ol class="bibliography">
  {%- assign papers_in_year = site.data.papers | where: "year", year -%}
  {%- for paper in papers_in_year -%}
    <li>{% include paper_entry.liquid paper=paper %}</li>
  {%- endfor -%}
  </ol>
{%- endfor -%}
</div>
