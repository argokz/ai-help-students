"""Embedding service using sentence-transformers."""
import asyncio
from typing import Union

from ..config import settings


class EmbeddingService:
    """
    Generates embeddings for text using multilingual sentence-transformers.
    
    Uses paraphrase-multilingual-mpnet-base-v2 which supports 50+ languages
    including Russian, Kazakh, and English.
    """
    
    def __init__(self):
        self._model = None
        self._model_lock = asyncio.Lock()
    
    @property
    def model(self):
        """Lazy load the embedding model."""
        if self._model is None:
            from sentence_transformers import SentenceTransformer
            
            self._model = SentenceTransformer(settings.embedding_model)
        return self._model
    
    @property
    def embedding_dimension(self) -> int:
        """Get the dimension of embeddings."""
        return self.model.get_sentence_embedding_dimension()
    
    async def embed(
        self,
        texts: Union[str, list[str]],
        normalize: bool = True,
    ) -> list[list[float]]:
        """
        Generate embeddings for text(s).
        
        Args:
            texts: Single text or list of texts
            normalize: Whether to L2 normalize embeddings
            
        Returns:
            List of embedding vectors (even for single text)
        """
        if isinstance(texts, str):
            texts = [texts]
        
        if not texts:
            return []
        
        async with self._model_lock:
            loop = asyncio.get_event_loop()
            embeddings = await loop.run_in_executor(
                None,
                self._embed_sync,
                texts,
                normalize
            )
            return embeddings
    
    def _embed_sync(
        self,
        texts: list[str],
        normalize: bool = True,
    ) -> list[list[float]]:
        """Synchronous embedding (runs in thread pool)."""
        embeddings = self.model.encode(
            texts,
            normalize_embeddings=normalize,
            show_progress_bar=False,
        )
        
        # Convert numpy arrays to lists
        return embeddings.tolist()
    
    async def embed_query(self, query: str) -> list[float]:
        """
        Embed a single query text.
        
        Args:
            query: Query text to embed
            
        Returns:
            Single embedding vector
        """
        embeddings = await self.embed([query])
        return embeddings[0] if embeddings else []
    
    async def embed_documents(
        self,
        documents: list[str],
        batch_size: int = 32,
    ) -> list[list[float]]:
        """
        Embed multiple documents efficiently.
        
        Args:
            documents: List of document texts
            batch_size: Number of documents to process at once
            
        Returns:
            List of embedding vectors
        """
        if not documents:
            return []
        
        all_embeddings = []
        
        for i in range(0, len(documents), batch_size):
            batch = documents[i:i + batch_size]
            batch_embeddings = await self.embed(batch)
            all_embeddings.extend(batch_embeddings)
        
        return all_embeddings


# Global instance
embedding_service = EmbeddingService()
