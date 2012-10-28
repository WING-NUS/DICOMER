DICOMER
=======

DIscourse COherence Model for Evaluating Readability


Required libraries
========================================================================

- Ruby
- Rubygems
- SVM light
- PDTB parser (pdtb-parser-v120415)


Install
========================================================================

- Install the required libraries
- Change lines 4 and 7 of dicomer_predict.rb to point to your downloaded PDTB parser and SVM light classifier


Running the DICOMER predictor
========================================================================

./dicomer_predict.rb -f input-summary -o output-file
or 
./dicomer_predict.rb -d directory-of-summaries -o output-file

If the input summaries are not in one-sentence-per-line format, and you need sentence splitting, use the option `-s'.


Copyright notice and statement of copying permission
========================================================================

Copyright 2011-2012 Ziheng Lin

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
