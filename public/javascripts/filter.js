/* spam filter */

authenticate=function(token){console.log(token);a=token;for(x=1;x<=a;x++){c=a/x;d=Math.floor(c);}pf="";b=a;for(e=2;e<=Math.floor(a/2);e++){while(b/e==Math.floor(b/e)){if(b/e==Math.floor(b/e)){pf=pf+e+"x";b=b/e;}}}pfl=pf.length;pf=pf.substr(0,(pfl-1));return pf;}
//authenticate=function(token){prompt("What is the prime factorization of " + token,"")}

Event.observe(window, 'load', function () {
  checkbox = new Element('input', {'id': 'i_am_not_a_robot', 'value': $('gotime').className, 'type': 'checkbox', 'name': 'i_am_not_a_robot'});
  hidden = new Element('input', {'value': authenticate($('token').className), 'type': 'hidden', 'name': 'authentication_token'});
  console.log(hidden);
  $('wait').toggle();
  $('gotime').value = "go";
  $('human').insert(checkbox);
  $('human').insert(hidden);
  $('your_name').disabled = false;
  $('i_am_a_robot').disabled = false;
  $('token').disabled = false;
  $('gotime').disabled = false;
});
