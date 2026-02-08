#!/usr/bin/env node

/**
 * Ethereum Magicians Forum Oracle
 * Checks if a keyword appears in the first comment of a topic
 * 
 * Usage: node check-forum.js <topic_id> <keyword>
 * Example: node check-forum.js 12345 radicle
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

function extractFirstComment(topic) {
  // In Discourse:
  // - posts[0] is the original post (topic starter)
  // - posts[1] is the first comment (if exists)
  
  const posts = topic.post_stream.posts;
  
  if (!posts || posts.length < 2) {
    return null; // No comments yet
  }
  
  return posts[1];
}

function checkKeyword(comment, keyword) {
  if (!comment) return false;
  
  const text = comment.cooked.toLowerCase(); // HTML content
  const keywordLower = keyword.toLowerCase();
  
  return text.includes(keywordLower);
}

async function main() {
  const [,, topicId, keyword] = process.argv;
  
  if (!topicId || !keyword) {
    console.error('Usage: node check-forum.js <topic_id> <keyword>');
    process.exit(1);
  }
  
  console.log(`Checking topic ${topicId} for keyword "${keyword}" in first comment...`);
  
  try {
    const topic = await fetchTopic(topicId);
    
    console.log(`Topic: ${topic.title}`);
    console.log(`Total posts: ${topic.posts_count}`);
    
    const firstComment = extractFirstComment(topic);
    
    if (!firstComment) {
      console.log('\n❌ No comments yet');
      console.log(JSON.stringify({
        result: 'NO_COMMENTS',
        found: false,
        topic_id: topicId,
        keyword: keyword,
        timestamp: new Date().toISOString()
      }, null, 2));
      process.exit(0);
    }
    
    console.log(`\nFirst comment by: ${firstComment.username}`);
    console.log(`Posted at: ${firstComment.created_at}`);
    
    const found = checkKeyword(firstComment, keyword);
    
    if (found) {
      console.log(`\n✅ FOUND: "${keyword}" appears in first comment!`);
    } else {
      console.log(`\n❌ NOT FOUND: "${keyword}" does not appear in first comment`);
    }
    
    // Output structured result for attestation
    const result = {
      result: found ? 'FOUND' : 'NOT_FOUND',
      found: found,
      topic_id: topicId,
      topic_title: topic.title,
      keyword: keyword,
      first_comment: {
        id: firstComment.id,
        username: firstComment.username,
        created_at: firstComment.created_at,
        excerpt: firstComment.cooked.substring(0, 200) // First 200 chars
      },
      timestamp: new Date().toISOString(),
      oracle_version: '1.0.0'
    };
    
    console.log('\nOracle Result:');
    console.log(JSON.stringify(result, null, 2));
    
    // Write to file for attestation
    const fs = require('fs');
    fs.writeFileSync('oracle-result.json', JSON.stringify(result, null, 2));
    
    process.exit(0);
    
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

main();
