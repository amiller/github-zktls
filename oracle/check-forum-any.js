#!/usr/bin/env node

/**
 * Extended Oracle: Check ANY comment (not just first)
 * 
 * Usage: node check-forum-any.js <topic_id> <keyword> [max_comments]
 * Example: node check-forum-any.js 27119 radicle 50
 */

const https = require('https');

async function fetchTopic(topicId) {
  return new Promise((resolve, reject) => {
    const url = `https://ethereum-magicians.org/t/${topicId}.json`;
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

function checkAllComments(topic, keyword, maxComments) {
  const posts = topic.post_stream.posts;
  
  if (!posts || posts.length < 2) {
    return { found: false, matches: [] };
  }
  
  const keywordLower = keyword.toLowerCase();
  const matches = [];
  
  // Skip first post (topic starter), check comments
  const commentsToCheck = posts.slice(1, Math.min(posts.length, maxComments + 1));
  
  for (const comment of commentsToCheck) {
    const text = comment.cooked.toLowerCase();
    if (text.includes(keywordLower)) {
      matches.push({
        position: matches.length + 1, // 1st match, 2nd match, etc.
        comment_number: comment.post_number, // Position in thread (1-indexed)
        id: comment.id,
        username: comment.username,
        created_at: comment.created_at,
        excerpt: comment.cooked.substring(0, 200)
      });
    }
  }
  
  return {
    found: matches.length > 0,
    matches: matches,
    first_match: matches.length > 0 ? matches[0] : null
  };
}

async function main() {
  const [,, topicId, keyword, maxComments = 100] = process.argv;
  
  if (!topicId || !keyword) {
    console.error('Usage: node check-forum-any.js <topic_id> <keyword> [max_comments]');
    process.exit(1);
  }
  
  console.log(`Checking topic ${topicId} for keyword "${keyword}" in ANY comment (max ${maxComments})...`);
  
  try {
    const topic = await fetchTopic(topicId);
    
    console.log(`Topic: ${topic.title}`);
    console.log(`Total posts: ${topic.posts_count}`);
    
    const result = checkAllComments(topic, keyword, parseInt(maxComments));
    
    if (result.found) {
      console.log(`\n✅ FOUND in ${result.matches.length} comment(s)!`);
      console.log(`\nFirst match:`);
      console.log(`  - Comment #${result.first_match.comment_number}`);
      console.log(`  - By: ${result.first_match.username}`);
      console.log(`  - At: ${result.first_match.created_at}`);
      
      if (result.matches.length > 1) {
        console.log(`\nAlso found in ${result.matches.length - 1} other comment(s)`);
      }
    } else {
      console.log(`\n❌ NOT FOUND in any of the ${topic.posts_count - 1} comments`);
    }
    
    // Output structured result
    const output = {
      result: result.found ? 'FOUND' : 'NOT_FOUND',
      found: result.found,
      settleable: true,  // Comments exist, can settle
      topic_id: topicId,
      topic_title: topic.title,
      keyword: keyword,
      oracle_type: 'any',  // This oracle checks any comment
      total_matches: result.matches.length,
      first_match: result.first_match,
      all_matches: result.matches,
      timestamp: new Date().toISOString(),
      oracle_version: '2.1.0-any-comment'
    };
    
    console.log('\nOracle Result:');
    console.log(JSON.stringify(output, null, 2));
    
    const fs = require('fs');
    fs.writeFileSync('oracle-result.json', JSON.stringify(output, null, 2));
    
    process.exit(0);
    
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

main();
