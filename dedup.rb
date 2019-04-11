require 'csv'
require 'text'
require 'json'
require 'sinatra'
require 'sinatra/json'

# 
# Utility Methods
# clean - Clean a row from file
# gen_key - generate a key based on columns you want to combine
# add_to - generate a key and use it to insert a hash into the master hash
# load_file - open csv file, parse, and build data structure
#

def clean(hline)
  
  #Clean First and Last Name
  for key in ['first_name','last_name']
    hline[key] = hline[key].downcase.strip
  end

end

def gen_key(keys, line_to_insert)

  full_key = []
  # Take the initialization arr keys and build the key from it
  for key in keys
    full_key << line_to_insert[key]
  end
  full_key.join('_')
end

def add_to(master, keys, line_to_insert)
  #generate hash key
  full_key = gen_key(keys, line_to_insert)

  #initialize hash slot with an empty array
  master[full_key] = [] if master[full_key].nil?
  
  #append the hash 
  master[full_key] << line_to_insert 

  master
end

def load_file(filename, master, key_arr)
  #initialize variables
  hash_line = {}
  clean_hash_line = {}

  #Set headers so line can be converted into hash
  CSV.foreach(filename, headers: true) do |line|
    hash_line = line.to_h

    #clean hash line
    clean_hash_line = clean(hash_line)
  
    #add hash_line to master
    master = add_to(master, key_arr, hash_line) 
  end
  master
end


#
# Categorize
#
# First sort out the entries into unique candidates
# and duplicates based on keys
#
# Secondary filtering of unique candidates 
#

def categorize(master, key_arr, duplicates, unique)
  unique_candidates = []
  to_remove = []

  #
  # Sort out entries in master into unique 
  # and duplicates categories
  #
  for key in master.keys
    if master[key].count > 1

      # Because there is more than one entry
      # Append specific reason for tagging this data as a duplicate
      duplicates << {'reason'=> "Duplicate key #{key}", 'data' => master[key] }
    else

      # Since there is only one entry we will add to the candidates
      unique_candidates << master[key][0]
    end
  end

  # Expensive here n-prime^2
  # It seems necessary in order to compare with
  # all other elements in the unique candidates list.
  #
  uc = unique_candidates
  for idx1 in (0...uc.count).to_a
    for idx2 in ((idx1+1)...uc.count).to_a

    #Generate the index keys for the elements
    #to be compared
    key1 = gen_key(key_arr, uc[idx1])
    key2 = gen_key(key_arr, uc[idx2])
    
   #Doing straight up computation, but we can
   #chain it. Example: if meta_sim > 0.95 then run 
   #levenshtein. If levenshtein is <= 2 then run
   #WhiteSimilarity. You would want the less accurate
   #algorithms to run first, this I'm not sure of
   ls =  Text::Levenshtein.distance(key1, key2) 
   white = Text::WhiteSimilarity.new
   meta1 = Text::Metaphone.metaphone(key1)
   meta2 = Text::Metaphone.metaphone(key2)
   meta_sim = white.similarity(meta1, meta2)
   sim = white.similarity(key1, key2)

   #TODO
   #puts Text::Metaphone.metaphone(uc[key2])
   #puts Text::Soundex.soundex(uc[key1])
   #puts Text::PorterStemming.stem(can['last_name'])

   # These are thresholds that were set by looking at the test data
   # This can be set dynamically based on whoever is manually checking these duplicate candidates
   if ls < 5 || sim > 0.85 || meta_sim > 0.85
     duplicates << {'reason'=> "Levenshtein: #{ls}, Sim: #{sim}, Sim on Metaphone: #{meta_sim}", 'data'=>[uc[idx1], uc[idx2]]}

     # Remove these entries later 
     to_remove << key1
     to_remove << key2
   end
   end
  end

  # Remove people that were candidates but were disqualified based on
  # further text algorithms
  for key in to_remove
    unique_candidates.delete_if{ |uc| gen_key(key_arr, uc) == key }
  end

  # Assign unique people to list
  unique = unique_candidates
  
  #Optional sort on last name 
  unique = unique.sort {|s1, s2| s1['last_name']<=>s2['last_name']}

  [duplicates, unique]
end



#
# Print out
#
def display(unique, duplicates)
  puts 'Unique'
  for item in unique 
    item = item
    puts item['first_name'] + ' ' + item['last_name'] + ' ' + item['email']
  end
    
  puts 'Multiple'
  for items in duplicates 
    for item in items
      #puts item['first_name'] + ' ' + item['last_name']
      puts item
    end
    puts '----------------------------'
  end
end


get '/results' do
  # Setup variables
  filename = 'advanced.csv'
  master = {}
  common_first_names = {'bill'=>'william'}
  duplicates = [] 
  unique = [] 
  key_arr = ['last_name', 'first_name', 'email']

  # Load
  master = load_file(filename, master, key_arr)

  # Categorize
  duplicates, unique = categorize(master, key_arr, duplicates, unique)
  results = {"uniques"=> unique, "duplicates"=> duplicates}

  json results 
end

get '/' do
# Setting up some styles and async js call function on the home page
# This will call the results page when the dom is loaded.
<<-EOS  
  <style>
  .unique {
    display: block;
  }
  .duplicate {
    display: block;
  }

  </style>
  <script>
  function create_td(tn){
    td = document.createElement('td');
    td.appendChild(document.createTextNode(tn));
    return td
  }

  function display(elm){
    text = elm['first_name'] + ',' +\
           elm['last_name'] + ',' +\
           elm['email'] + ',' +\
           elm['phone'] + ',' +\
           elm['company'] + ',' +\
           elm['address1'] + ',' +\
           elm['address2'] + ',' +\
           elm['zip'] + ',' +\
           elm['city'] + ',' +\
           elm['state']
    return document.createTextNode(text); 
  }

  function display_duplicate_reason(elm){
    tn = document.createTextNode('Reason: ' + elm.reason);
    return tn;
  }

  function display_duplicate(ul, elm){  
    elm.data.forEach(item =>{
      li = document.createElement('li');
      li.appendChild(display(item));
      ul.appendChild(li);
    });
  }

  function display_uniques(elm){
    return display(elm);
  }

  function getRequest(url, callback, params, response_type, callback_params) {
    var request = new XMLHttpRequest();
    var method = 'GET';

    if(url.charAt(0) != '/'){
      url = '/' + url;
    }
    
    request.onload = function() {
        if(request.status === 200) { 
          let checkType = request.getResponseHeader('content-type');
          if (checkType == 'application/json') {
            raw = JSON.parse(request.responseText);
            d = document.querySelector('.duplicates');
            ul = document.createElement('ul');
            for (var i = 0; i < raw.duplicates.length; i++) {
              li = document.createElement('li');
              li.appendChild(display_duplicate_reason(raw.duplicates[i]));
              ul.appendChild(li);
              display_duplicate(ul, raw.duplicates[i]);
              li = document.createElement('li');
              li.appendChild(document.createTextNode(''));
              ul.appendChild(li);
            }
            d.appendChild(ul);

            u = document.querySelector('.uniques');
            ul = document.createElement('ul');
            for (var i = 0; i < raw.uniques.length; i++) {
              li = document.createElement('li');
              li.appendChild(display_uniques(raw.uniques[i]));
              ul.appendChild(li)
            }
            u.appendChild(ul);
            
          }
        } 
      }

    request.open(method, url);
    request.send(null);
  }

  document.addEventListener('DOMContentLoaded', function(){
    getRequest('/results')
  });
  </script>
  <body>
    <h1>Find Duplicates Challenge</h1>
    <h3>Unique Entries</h3>
    <div class="uniques">
    </div>
    <h3>Duplicate Entries</h3>
    <div class="duplicates">
    </div>
  </body>
  
EOS
end
