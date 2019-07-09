
# Table of Contents

1.  [slate](#org59127d7)
    1.  [Overview](#org0103b8b)
    2.  [Usage](#org69fa357)
    3.  [Installation](#org7eda32a)


<a id="org59127d7"></a>

# slate

Figure out what you have slated&#x2026;..

![img](slate.png)


<a id="org0103b8b"></a>

## Overview

slate is an app built in emacs that gathers TODO entries from a directory of org files. It does this using rg so many files can quickly be scanned.

The list can be incrementally filtered down by typing and hitting enter will take you to the selected TODO entry.

The list is ordered by priority and contains priority, file name, line number, the text, and tags.


<a id="org69fa357"></a>

## Usage

Slate can be started by calling slate. If you want to refresh the list call slate-refresh.


<a id="org7eda32a"></a>

## Installation

Slate requires that rg be installed. Once rg is installed it can be installed with straight like:

    (use-package slate
      :defer t
      :straight (slate :type git :host github :repo "jonathanhope/slate")
      :commands (slate slate-refresh))
