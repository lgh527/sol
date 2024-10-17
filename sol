const web3 = require('@solana/web3.js');
const axios = require('axios');

const connection = new web3.Connection(
  web3.clusterApiUrl('mainnet-beta'),
  'confirmed'
);

// Replace with your own public key and secret key
const yourPublicKey = new web3.PublicKey('<9wjAii2KZekzYWfDQxyQv5jsSNdyrNr6RPvC9hxeqJFk>');
const yourKeyPair = web3.Keypair.fromSecretKey(Uint8Array.from([/* 56RfA93WKD7yKUrHGoRTmFr3WPH55iq9jxSqBA6R6sEhatfsphB5brMvERzyD1MCeRu7RE3RDzPCyWfw6qaXBwDC */]));

// Define the RugCheck and Moni Discover API endpoints
const rugCheckApiUrl = 'https://rugcheck.xyz/api/v1/check'; // Adjust to the actual endpoint
const moniDiscoverApiUrl = 'https://discover.getmoni.io/api/v1/project'; // Adjust based on actual Moni API

// Amount to buy: 0.15 SOL = 150,000,000 lamports
const buyAmountInLamports = 0.15 * web3.LAMPORTS_PER_SOL;

// Preset minimum sell amount in SOL (e.g., 0.1 SOL = 100,000,000 lamports)
const minimumSellAmountInLamports = 0.1 * web3.LAMPORTS_PER_SOL;

// Function to check token contract with RugCheck
async function checkTokenContract(tokenContractAddress) {
  try {
    const response = await axios.get(`${rugCheckApiUrl}?contract=${tokenContractAddress}`);
    
    if (response.data.isSafe) {
      console.log('Token is verified and safe to buy.');
      return true; // Safe to buy
    } else {
      console.log('Warning: This token has issues according to RugCheck.');
      return false; // Not safe to buy
    }
  } catch (error) {
    console.error('Error checking token with RugCheck:', error);
    return false; // Treat as not safe if an error occurs
  }
}

// Function to check the project's livestream status with Moni Discover
async function checkProjectLivestream(tokenContractAddress) {
  try {
    // Make a request to Moni Discover for the project info
    const response = await axios.get(`${moniDiscoverApiUrl}?contract=${tokenContractAddress}`);
    
    // Check if the project has an active livestream and more than 25 viewers
    if (response.data.project && response.data.project.livestream) {
      const livestreamInfo = response.data.project.livestream;
      
      if (livestreamInfo.isLive && livestreamInfo.viewerCount > 25) {
        console.log(`Project has an active livestream with ${livestreamInfo.viewerCount} viewers.`);
        return true; // Safe to buy based on livestream activity
      } else {
        console.log('Livestream is not active or doesn’t have enough viewers.');
        return false; // Not safe based on livestream data
      }
    } else {
      console.log('No livestream found for the project.');
      return false; // No livestream activity
    }
  } catch (error) {
    console.error('Error checking livestream with Moni Discover:', error);
    return false; // Treat as not safe if an error occurs
  }
}

// Function to check liquidity and market cap
async function checkLiquidityAndMarketCap(tokenContractAddress) {
  try {
    // Make an API request to check liquidity and market cap (use appropriate API)
    const response = await axios.get(`https://api.coingecko.com/api/v3/coins/solana/contract/${tokenContractAddress}`);
    
    if (response.data && response.data.market_data) {
      const liquidity = response.data.market_data.liquidity;  // Get liquidity info
      const marketCap = response.data.market_data.market_cap.usd;  // Get market cap in USD

      console.log(`Liquidity: ${liquidity}, Market Cap: ${marketCap}`);

      if (liquidity > 10000 && marketCap > 1000000) {  // Example thresholds
        console.log('Token has sufficient liquidity and market cap.');
        return true; // Safe to sell
      } else {
        console.log('Insufficient liquidity or market cap.');
        return false; // Not safe to sell
      }
    } else {
      console.log('Liquidity or market cap data unavailable.');
      return false;
    }
  } catch (error) {
    console.error('Error checking liquidity and market cap:', error);
    return false; // Treat as not safe if an error occurs
  }
}

// Function to sell the token
async function sellToken(tokenContractAddress, sellAmountInLamports) {
  // Check liquidity and market cap before selling
  const isSellSafe = await checkLiquidityAndMarketCap(tokenContractAddress);
  
  if (isSellSafe && sellAmountInLamports >= minimumSellAmountInLamports) {
    console.log(`Selling ${sellAmountInLamports / web3.LAMPORTS_PER_SOL} SOL worth of tokens...`);

    // Construct and send the transaction to sell the token
    const transaction = new web3.Transaction().add(
      web3.SystemProgram.transfer({
        fromPubkey: yourPublicKey,
        toPubkey: new web3.PublicKey(tokenContractAddress), // Send tokens to target token address
        lamports: sellAmountInLamports, // Define the amount you want to sell
      })
    );

    try {
      const signature = await web3.sendAndConfirmTransaction(connection, transaction, [yourKeyPair]);
      console.log('Transaction successful with signature:', signature);
    } catch (err) {
      console.error('Transaction failed:', err);
    }
  } else {
    console.log('Sell conditions not met (insufficient liquidity, market cap, or sell amount too low).');
  }
}

// Main function to snipe and sell a token
async function snipeAndSellToken(tokenContractAddress) {
  // Step 1: Check if token is safe via RugCheck
  const isTokenSafe = await checkTokenContract(tokenContractAddress);

  if (isTokenSafe) {
    // Step 2: Check the project's livestream status with Moni Discover
    const isLivestreamSafe = await checkProjectLivestream(tokenContractAddress);

    if (isLivestreamSafe) {
      // Step 3: Proceed with purchasing the token if RugCheck and livestream checks are safe
      console.log('Proceeding to buy the token...');

      // Construct and send the transaction to buy the token
      const transaction = new web3.Transaction().add(
        web3.SystemProgram.transfer({
          fromPubkey: yourPublicKey,
          toPubkey: new web3.PublicKey(tokenContractAddress), // Target token address
          lamports: buyAmountInLamports, // Set the buy amount to 0.15 SOL
        })
      );

      try {
        const signature = await web3.sendAndConfirmTransaction(connection, transaction, [yourKeyPair]);
        console.log('Transaction successful with signature:', signature);

        // Step 4: Now attempt to sell after purchasing
        await sellToken(tokenContractAddress, buyAmountInLamports); // Sell the same amount you bought
      } catch (err) {
        console.error('Transaction failed:', err);
      }
    } else {
      console.log('Aborting purchase: Livestream check failed.');
    }
  } else {
    console.log('Aborting purchase: Token is not safe.');
  }
}

// Listen for new token creation events on Solana
async function listenForNewTokens() {
  connection.onProgramAccountChange(
    new web3.PublicKey('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'), // Token program ID for SPL tokens
    async (info) => {
      const tokenAccountInfo = web3.AccountLayout.decode(info.accountInfo.data);
      const tokenAddress = new web3.PublicKey(tokenAccountInfo.mint);
      console.log(`New token detected: ${tokenAddress.toString()}`);

      // Snipe and sell the new token
      await snipeAndSellToken(tokenAddress.toString());
    },
    'confirmed'
  );
}

// Start listening for new tokens
listenForNewTokens();
