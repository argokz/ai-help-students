"""Vector store service using ChromaDB."""
import asyncio
from typing import Optional

import chromadb
from chromadb.config import Settings as ChromaSettings

from ..config import settings
from .chunker_service import chunker_service
from .embedding_service import embedding_service


class VectorStore:
    """
    ChromaDB-based vector store for lecture chunk retrieval.
    
    Each lecture gets its own collection for isolation and easy deletion.
    """
    
    def __init__(self):
        self._client = None
        self._lock = asyncio.Lock()
    
    @property
    def client(self) -> chromadb.ClientAPI:
        """Lazy load ChromaDB client."""
        if self._client is None:
            self._client = chromadb.PersistentClient(
                path=str(settings.chroma_dir),
                settings=ChromaSettings(
                    anonymized_telemetry=False,
                    allow_reset=True,
                )
            )
        return self._client
    
    def _collection_name(self, lecture_id: str) -> str:
        """Generate collection name for a lecture."""
        # ChromaDB requires alphanumeric names starting with letter
        return f"lecture_{lecture_id.replace('-', '_')}"
    
    async def index_lecture(
        self,
        lecture_id: str,
        segments: list[dict],
    ) -> int:
        """
        Index lecture segments into vector store.
        
        Args:
            lecture_id: Unique lecture identifier
            segments: List of {start, end, text} from ASR
            
        Returns:
            Number of chunks indexed
        """
        async with self._lock:
            # Chunk the segments
            chunks = chunker_service.chunk_segments(segments)
            
            if not chunks:
                return 0
            
            # Generate embeddings
            texts = [chunk["text"] for chunk in chunks]
            embeddings = await embedding_service.embed_documents(texts)
            
            # Create or get collection
            collection = self.client.get_or_create_collection(
                name=self._collection_name(lecture_id),
                metadata={"lecture_id": lecture_id}
            )
            
            # Prepare data for ChromaDB
            ids = [f"{lecture_id}_chunk_{i}" for i in range(len(chunks))]
            metadatas = [
                {
                    "lecture_id": lecture_id,
                    "start_time": chunk["start_time"],
                    "end_time": chunk["end_time"],
                    "chunk_index": i,
                }
                for i, chunk in enumerate(chunks)
            ]
            documents = texts
            
            # Add to collection
            collection.add(
                ids=ids,
                embeddings=embeddings,
                metadatas=metadatas,
                documents=documents,
            )
            
            return len(chunks)
    
    async def search(
        self,
        lecture_id: str,
        query: str,
        top_k: int = 5,
        min_score: float = 0.3,
    ) -> list[dict]:
        """
        Search for relevant chunks in a lecture.
        
        Args:
            lecture_id: Lecture to search in
            query: Search query
            top_k: Number of results to return
            min_score: Minimum similarity score (0-1)
            
        Returns:
            List of relevant chunks with scores
        """
        async with self._lock:
            collection_name = self._collection_name(lecture_id)
            
            try:
                collection = self.client.get_collection(name=collection_name)
            except ValueError:
                # Collection doesn't exist
                return []
            
            # Get query embedding
            query_embedding = await embedding_service.embed_query(query)
            
            # Search
            results = collection.query(
                query_embeddings=[query_embedding],
                n_results=top_k,
                include=["documents", "metadatas", "distances"]
            )
            
            # Process results
            chunks = []
            
            if results and results["documents"] and results["documents"][0]:
                for i, doc in enumerate(results["documents"][0]):
                    metadata = results["metadatas"][0][i]
                    # ChromaDB returns L2 distance, convert to similarity
                    distance = results["distances"][0][i]
                    # For normalized embeddings, distance is in [0, 2]
                    # Convert to similarity in [0, 1]
                    score = 1 - (distance / 2)
                    
                    if score >= min_score:
                        chunks.append({
                            "text": doc,
                            "start_time": metadata["start_time"],
                            "end_time": metadata["end_time"],
                            "score": round(score, 3),
                        })
            
            # Sort by score descending
            chunks.sort(key=lambda x: x["score"], reverse=True)
            
            return chunks

    async def search_all_lectures(
        self,
        lecture_ids: list[str],
        query: str,
        top_k_per_lecture: int = 3,
        min_score: float = 0.25,
    ) -> list[dict]:
        """
        Поиск по всем указанным лекциям. Возвращает список {lecture_id, chunks}.
        """
        if not lecture_ids or not query.strip():
            return []
        all_results = []
        query_embedding = await embedding_service.embed_query(query)
        async with self._lock:
            for lecture_id in lecture_ids:
                collection_name = self._collection_name(lecture_id)
                try:
                    collection = self.client.get_collection(name=collection_name)
                except ValueError:
                    continue
                results = collection.query(
                    query_embeddings=[query_embedding],
                    n_results=top_k_per_lecture,
                    include=["documents", "metadatas", "distances"],
                )
                chunks = []
                if results and results["documents"] and results["documents"][0]:
                    for i, doc in enumerate(results["documents"][0]):
                        metadata = results["metadatas"][0][i]
                        distance = results["distances"][0][i]
                        score = 1 - (distance / 2)
                        if score >= min_score:
                            chunks.append({
                                "text": doc,
                                "start_time": metadata.get("start_time", 0),
                                "end_time": metadata.get("end_time", 0),
                                "score": round(score, 3),
                            })
                if chunks:
                    all_results.append({"lecture_id": lecture_id, "chunks": chunks})
        return all_results
    
    async def delete_lecture(self, lecture_id: str) -> bool:
        """
        Delete all indexed data for a lecture.
        
        Args:
            lecture_id: Lecture to delete
            
        Returns:
            True if deleted, False if not found
        """
        async with self._lock:
            collection_name = self._collection_name(lecture_id)
            
            try:
                self.client.delete_collection(name=collection_name)
                return True
            except ValueError:
                return False
    
    async def get_lecture_chunk_count(self, lecture_id: str) -> int:
        """Get number of chunks indexed for a lecture."""
        async with self._lock:
            collection_name = self._collection_name(lecture_id)
            
            try:
                collection = self.client.get_collection(name=collection_name)
                return collection.count()
            except ValueError:
                return 0


# Global instance
vector_store = VectorStore()
